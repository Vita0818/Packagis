import Foundation

public protocol CredentialProvider: Sendable {
    func headers(for target: ProviderTarget) async throws -> [String: String]
}

public struct NoCredentialProvider: CredentialProvider {
    public init() {}

    public func headers(for _: ProviderTarget) async throws -> [String: String] {
        [:]
    }
}

public struct ClosureCredentialProvider: CredentialProvider {
    private let resolver: @Sendable (ProviderTarget) async throws -> [String: String]

    public init(
        _ resolver: @escaping @Sendable (ProviderTarget) async throws -> [String: String]
    ) {
        self.resolver = resolver
    }

    public func headers(for target: ProviderTarget) async throws -> [String: String] {
        try await resolver(target)
    }
}

public struct ModelStream: AsyncSequence, Sendable {
    public typealias Element = ModelStreamEvent

    private let stream: AsyncThrowingStream<ModelStreamEvent, Error>
    private let cancellation: ModelStreamCancellation

    init(
        _ stream: AsyncThrowingStream<ModelStreamEvent, Error>,
        cancellation: ModelStreamCancellation
    ) {
        self.stream = stream
        self.cancellation = cancellation
    }

    public func makeAsyncIterator()
        -> AsyncThrowingStream<ModelStreamEvent, Error>.Iterator
    {
        stream.makeAsyncIterator()
    }

    public func cancel() {
        cancellation.cancel()
    }
}

public struct PackagisClient: Sendable {
    private let transport: any HTTPTransport
    private let credentials: any CredentialProvider

    public init(
        transport: any HTTPTransport = MockTransport(),
        credentials: any CredentialProvider = NoCredentialProvider()
    ) {
        self.transport = transport
        self.credentials = credentials
    }

    public func prepare(
        _ request: ModelRequest,
        profile: EnvironmentProfile,
        target: ProviderTarget,
        referenceDate: Date
    ) throws -> PreparedRequest {
        let environment = try EnvironmentCompiler.compile(
            profile: profile,
            request: request,
            target: target,
            referenceDate: referenceDate
        )

        return try ProviderAdapters.prepare(
            request: request,
            profile: profile,
            target: target,
            compiledEnvironment: environment
        )
    }

    public func send(_ preparedRequest: PreparedRequest) async throws -> ModelResponse {
        let preview = try preparedRequest.preview(for: .single)
        let request = try await authorizedRequest(
            preview.request,
            target: preparedRequest.target
        )
        let response = try await transport.execute(request)

        guard (200 ... 299).contains(response.statusCode) else {
            throw PackagisError.httpStatus(
                response.statusCode,
                message: ProviderAdapters.decodeHTTPErrorMessage(response.body)
            )
        }

        let decoded = try ProviderAdapters.decodeResponse(
            provider: preparedRequest.target.provider,
            data: response.body
        )

        return ModelResponse(
            text: decoded.text,
            completion: decoded.completion,
            statusCode: response.statusCode,
            headers: response.headers,
            rawBody: response.body,
            report: preparedRequest.report
        )
    }

    public func stream(_ preparedRequest: PreparedRequest) async throws -> ModelStream {
        let preview = try preparedRequest.preview(for: .streaming)
        let request = try await authorizedRequest(
            preview.request,
            target: preparedRequest.target
        )
        let response = try await transport.openStream(request)

        guard (200 ... 299).contains(response.statusCode) else {
            let body = try await boundedErrorBody(response.body)
            throw PackagisError.httpStatus(
                response.statusCode,
                message: ProviderAdapters.decodeHTTPErrorMessage(body)
            )
        }

        let contentType = header("Content-Type", in: response.headers)
        guard contentType?.lowercased().contains("text/event-stream") == true else {
            throw PackagisError.invalidContentType(contentType)
        }

        let provider = preparedRequest.target.provider
        let source = response.body

        let cancellation = ModelStreamCancellation()
        let events = AsyncThrowingStream<ModelStreamEvent, Error>(
            bufferingPolicy: .bufferingOldest(32)
        ) { continuation in
                let consumer = Task {
                    do {
                        var parser = SSEParser()
                        var decoder = ProviderStreamDecoder(provider: provider)
                        var receivedTerminalEvent = false

                        streamLoop: for try await chunk in source {
                            try Task.checkCancellation()
                            for event in try parser.feed(chunk) {
                                for decoded in try decoder.decode(event) {
                                    try await yieldWithBackpressure(
                                        decoded,
                                        to: continuation
                                    )
                                    if decoded.isTerminal {
                                        receivedTerminalEvent = true
                                        break streamLoop
                                    }
                                }
                            }
                        }

                        if !receivedTerminalEvent {
                            finishLoop: for event in try parser.finish() {
                                for decoded in try decoder.decode(event) {
                                    try await yieldWithBackpressure(
                                        decoded,
                                        to: continuation
                                    )
                                    if decoded.isTerminal {
                                        receivedTerminalEvent = true
                                        break finishLoop
                                    }
                                }
                            }
                        }

                        guard receivedTerminalEvent else {
                            throw PackagisError.malformedResponse(
                                "Stream ended before the provider completion marker."
                            )
                        }

                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    consumer.cancel()
                }
                cancellation.attach(consumer)
            }

        return ModelStream(events, cancellation: cancellation)
    }

    private func authorizedRequest(
        _ request: HTTPRequest,
        target: ProviderTarget
    ) async throws -> HTTPRequest {
        let credentialHeaders = try await credentials.headers(for: target)
        var result = request

        for (name, value) in credentialHeaders {
            guard target.provider.allowedCredentialHeaders.contains(name.lowercased()) else {
                throw PackagisError.invalidCredentialHeader(name)
            }

            guard
                !name.unicodeScalars.contains(
                    where: { CharacterSet.controlCharacters.contains($0) }
                ),
                !value.unicodeScalars.contains(
                    where: { CharacterSet.controlCharacters.contains($0) }
                )
            else {
                throw PackagisError.invalidCredentialHeader(name)
            }

            result.headers[name] = value
        }

        return result
    }

    private func boundedErrorBody(
        _ body: HTTPBodyStream,
        limit: Int = 65_536
    ) async throws -> Data {
        var result = Data()
        result.reserveCapacity(min(limit, 4_096))

        for try await chunk in body {
            let remaining = limit - result.count
            guard remaining > 0 else {
                break
            }
            result.append(contentsOf: chunk.prefix(remaining))
            if result.count == limit {
                break
            }
        }

        return result
    }

    private func header(
        _ name: String,
        in headers: [String: String]
    ) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

final class ModelStreamCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isCancelled = false

    func attach(_ task: Task<Void, Never>) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            task.cancel()
            return
        }
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }

    deinit {
        cancel()
    }
}

private extension ModelStreamEvent {
    var isTerminal: Bool {
        switch self {
        case .completed, .incomplete, .refused:
            true
        case .started, .textDelta, .discardedText, .providerEvent:
            false
        }
    }
}

private extension ProviderID {
    var allowedCredentialHeaders: Set<String> {
        switch self {
        case .openAIResponses:
            ["authorization", "openai-organization", "openai-project"]
        case .anthropicMessages:
            ["x-api-key", "authorization", "anthropic-beta"]
        case .openRouterChat:
            ["authorization"]
        }
    }
}
