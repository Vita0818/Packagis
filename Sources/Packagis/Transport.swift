import Foundation

public struct HTTPBodyStream: AsyncSequence, Sendable {
    public typealias Element = Data

    private let stream: AsyncThrowingStream<Data, Error>

    public init(_ stream: AsyncThrowingStream<Data, Error>) {
        self.stream = stream
    }

    public func makeAsyncIterator() -> AsyncThrowingStream<Data, Error>.Iterator {
        stream.makeAsyncIterator()
    }
}

public struct HTTPStreamResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: HTTPBodyStream

    public init(
        statusCode: Int,
        headers: [String: String],
        body: HTTPBodyStream
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func execute(_ request: HTTPRequest) async throws -> HTTPResponse
    func openStream(_ request: HTTPRequest) async throws -> HTTPStreamResponse
}

public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let redirectDelegate: RedirectRejectingDelegate

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let delegate = RedirectRejectingDelegate()
        self.redirectDelegate = delegate
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: urlRequest(from: request))
        guard let response = response as? HTTPURLResponse else {
            throw PackagisError.invalidHTTPResponse
        }

        return HTTPResponse(
            statusCode: response.statusCode,
            headers: headers(from: response),
            body: data
        )
    }

    public func openStream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let (bytes, response) = try await session.bytes(for: urlRequest(from: request))
        guard let response = response as? HTTPURLResponse else {
            throw PackagisError.invalidHTTPResponse
        }

        let body = HTTPBodyStream(
            AsyncThrowingStream(bufferingPolicy: .bufferingOldest(16)) { continuation in
                let producer = Task {
                    do {
                        var chunk = Data()
                        chunk.reserveCapacity(4_096)

                        for try await byte in bytes {
                            try Task.checkCancellation()
                            chunk.append(byte)

                            if byte == 0x0A || byte == 0x0D || chunk.count >= 4_096 {
                                try await yieldWithBackpressure(chunk, to: continuation)
                                chunk.removeAll(keepingCapacity: true)
                            }
                        }

                        if !chunk.isEmpty {
                            try await yieldWithBackpressure(chunk, to: continuation)
                        }

                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    producer.cancel()
                }
            }
        )

        return HTTPStreamResponse(
            statusCode: response.statusCode,
            headers: headers(from: response),
            body: body
        )
    }

    private func urlRequest(from request: HTTPRequest) -> URLRequest {
        var result = URLRequest(url: request.url)
        result.httpMethod = request.method
        result.httpBody = request.body
        for (name, value) in request.headers {
            result.setValue(value, forHTTPHeaderField: name)
        }
        return result
    }

    private func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { result, item in
            guard
                let name = item.key as? String,
                let value = item.value as? String
            else {
                return
            }
            result[name] = value
        }
    }
}

func yieldWithBackpressure<Element: Sendable>(
    _ element: Element,
    to continuation: AsyncThrowingStream<Element, Error>.Continuation
) async throws {
    while true {
        try Task.checkCancellation()

        switch continuation.yield(element) {
        case .enqueued:
            return
        case .dropped:
            try await Task<Never, Never>.sleep(nanoseconds: 1_000_000)
        case .terminated:
            throw CancellationError()
        @unknown default:
            throw CancellationError()
        }
    }
}

private final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum MockReply: Sendable {
    case response(HTTPResponse)
    case stream(
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "text/event-stream"],
        chunks: [Data]
    )
}

public actor MockTransport: HTTPTransport {
    private var replies: [MockReply]
    private var requests: [HTTPRequest] = []

    public init(replies: [MockReply] = []) {
        self.replies = replies
    }

    public func enqueue(_ reply: MockReply) {
        replies.append(reply)
    }

    public func recordedRequests() -> [HTTPRequest] {
        requests
    }

    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !replies.isEmpty else {
            throw PackagisError.noMockReply
        }

        let reply = replies.removeFirst()
        guard case let .response(response) = reply else {
            throw PackagisError.wrongMockReplyKind
        }
        return response
    }

    public func openStream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        requests.append(request)
        guard !replies.isEmpty else {
            throw PackagisError.noMockReply
        }

        let reply = replies.removeFirst()
        guard case let .stream(statusCode, headers, chunks) = reply else {
            throw PackagisError.wrongMockReplyKind
        }

        let body = HTTPBodyStream(
            AsyncThrowingStream { continuation in
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        )

        return HTTPStreamResponse(
            statusCode: statusCode,
            headers: headers,
            body: body
        )
    }
}
