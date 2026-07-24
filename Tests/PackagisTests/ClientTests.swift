import Foundation
import XCTest
@testable import Packagis

final class ClientTests: XCTestCase {
    func testBoundedBackpressurePreservesEveryElement() async throws {
        let stream = AsyncThrowingStream<Int, Error>(
            bufferingPolicy: .bufferingOldest(1)
        ) { continuation in
            Task {
                do {
                    for value in 0 ..< 100 {
                        try await yieldWithBackpressure(value, to: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        var values: [Int] = []
        for try await value in stream {
            values.append(value)
            try await Task<Never, Never>.sleep(nanoseconds: 50_000)
        }

        XCTAssertEqual(values, Array(0 ..< 100))
    }

    func testExplicitModelStreamCancellationStopsTheSource() async throws {
        let probe = StreamTerminationProbe()
        let state = HangingStreamState(probe: probe)
        let client = PackagisClient(
            transport: CancellationProbeTransport(state: state)
        )
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        let stream = try await client.stream(prepared)
        var iterator = stream.makeAsyncIterator()
        let firstEvent = try await iterator.next()
        XCTAssertEqual(firstEvent, .started)

        stream.cancel()

        for _ in 0 ..< 100 {
            if await probe.didTerminate() {
                break
            }
            try await Task<Never, Never>.sleep(nanoseconds: 1_000_000)
        }
        let didTerminate = await probe.didTerminate()
        XCTAssertTrue(didTerminate)
    }

    func testDefaultClientUsesMockTransport() async throws {
        let client = PackagisClient()
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        do {
            _ = try await client.send(prepared)
            XCTFail("Expected the empty default mock queue to reject the request.")
        } catch let error as PackagisError {
            XCTAssertEqual(error, .noMockReply)
        }
    }

    func testMockSendNormalizesOpenAIResponse() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: Data(#"{"output_text":"Hello"}"#.utf8)
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.report.profileID, "us-new-york-en")
    }

    func testOpenAINonStreamingIncompletePreservesReason() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        """
                        {"status":"incomplete","output_text":"Partial",\
                        "incomplete_details":{"reason":"max_output_tokens"}}
                        """.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "Partial")
        XCTAssertEqual(
            response.completion,
            .incomplete(reason: "max_output_tokens")
        )
    }

    func testOpenAIIncompleteMayHaveNoTextOutput() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        """
                        {"status":"incomplete","output":[],\
                        "incomplete_details":{"reason":"max_output_tokens"}}
                        """.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "")
        XCTAssertEqual(
            response.completion,
            .incomplete(reason: "max_output_tokens")
        )
    }

    func testOpenAIRefusalIsPreservedAsRefusedOutput() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        """
                        {"status":"completed","output":[{"content":[{"type":"refusal",\
                        "refusal":"Cannot help with that."}]}]}
                        """.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "Cannot help with that.")
        XCTAssertEqual(response.completion, .refused)
    }

    func testMockSendNormalizesAnthropicResponse() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"content":[{"type":"text","text":"Hel"},{"type":"tool_use"},{"type":"text","text":"lo"}],"stop_reason":"end_turn"}"#.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .anthropicMessages,
                modelID: "mock-claude"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.completion, .completed)
    }

    func testAnthropicMaxTokensIsIncomplete() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"content":[{"type":"text","text":"Partial"}],"stop_reason":"max_tokens"}"#.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .anthropicMessages,
                modelID: "mock-claude"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "Partial")
        XCTAssertEqual(response.completion, .incomplete(reason: "max_tokens"))
    }

    func testAnthropicNonStreamingRefusalDiscardsPartialText() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"content":[{"type":"text","text":"Partial"}],"stop_reason":"refusal"}"#.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .anthropicMessages,
                modelID: "mock-claude"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "")
        XCTAssertEqual(response.completion, .refused)
    }

    func testAnthropicEmptyEndTurnIsCompleted() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"content":[],"stop_reason":"end_turn"}"#.utf8)
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .anthropicMessages,
                modelID: "mock-claude"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "")
        XCTAssertEqual(response.completion, .completed)
    }

    func testMockSendNormalizesOpenRouterResponse() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}]}"#.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openRouterChat,
                modelID: "openai/mock"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.completion, .completed)
    }

    func testOpenRouterLengthFinishIsIncomplete() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"choices":[{"message":{"content":"Partial"},"finish_reason":"length"}]}"#.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openRouterChat,
                modelID: "openai/mock"
            ),
            referenceDate: fixedDate()
        )

        let response = try await client.send(prepared)
        XCTAssertEqual(response.text, "Partial")
        XCTAssertEqual(response.completion, .incomplete(reason: "length"))
    }

    func testOpenRouterNonStreamingChoiceErrorIsRejected() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(
                        """
                        {"choices":[{"message":{"content":"partial"},"finish_reason":"error",\
                        "error":{"message":"upstream failed"}}]}
                        """.utf8
                    )
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openRouterChat,
                modelID: "openai/mock"
            ),
            referenceDate: fixedDate()
        )

        do {
            _ = try await client.send(prepared)
            XCTFail("Expected the embedded OpenRouter error to be rejected.")
        } catch let error as PackagisError {
            XCTAssertEqual(error, .providerError("upstream failed"))
        }
    }

    func testNonStreamingHTTPErrorIncludesProviderMessage() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 429,
                    body: Data(#"{"error":{"message":"rate limited"}}"#.utf8)
                )
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        do {
            _ = try await client.send(prepared)
            XCTFail("Expected the HTTP error to be rejected.")
        } catch let error as PackagisError {
            XCTAssertEqual(error, .httpStatus(429, message: "rate limited"))
        }
    }

    func testCredentialsAreInjectedOnlyAtSendTime() async throws {
        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    body: Data(#"{"output_text":"Hello"}"#.utf8)
                )
            ),
        ])
        let credentials = ClosureCredentialProvider { _ in
            ["Authorization": "Bearer mock-secret"]
        }
        let client = PackagisClient(
            transport: transport,
            credentials: credentials
        )
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        let preview = try prepared.preview(for: .single)
        XCTAssertNil(preview.request.headers["Authorization"])

        _ = try await client.send(prepared)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer mock-secret")
    }

    func testOpenAIStreamNormalization() async throws {
        let fixture = """
        event: response.created
        data: {"type":"response.created"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hel"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"lo"}

        event: response.completed
        data: {"type":"response.completed"}

        data: [DONE]

        """

        let events = try await normalizedEvents(
            provider: .openAIResponses,
            chunks: split(Data(fixture.utf8), every: 7)
        )

        XCTAssertEqual(events, [
            .started,
            .textDelta("Hel"),
            .textDelta("lo"),
            .completed,
        ])
    }

    func testOpenAIIncompleteStreamIsATerminalEvent() async throws {
        let fixture = """
        event: response.created
        data: {"type":"response.created"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Partial"}

        event: response.incomplete
        data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}

        data: [DONE]

        """

        let events = try await normalizedEvents(
            provider: .openAIResponses,
            chunks: split(Data(fixture.utf8), every: 6)
        )

        XCTAssertEqual(events, [
            .started,
            .textDelta("Partial"),
            .incomplete(reason: "max_output_tokens"),
        ])
    }

    func testOpenAIRefusalWaitsForResponseCompleted() async throws {
        let fixture = """
        event: response.refusal.delta
        data: {"type":"response.refusal.delta","delta":"Cannot help."}

        event: response.refusal.done
        data: {"type":"response.refusal.done","refusal":"Cannot help."}

        event: response.completed
        data: {"type":"response.completed","response":{"usage":{"total_tokens":4}}}

        """

        let events = try await normalizedEvents(
            provider: .openAIResponses,
            chunks: split(Data(fixture.utf8), every: 6)
        )

        XCTAssertEqual(events.first, .textDelta("Cannot help."))
        XCTAssertTrue(events.contains { event in
            if case .providerEvent = event {
                return true
            }
            return false
        })
        XCTAssertEqual(events.last, .refused)
    }

    func testAnthropicStreamNormalization() async throws {
        let fixture = """
        event: message_start
        data: {"type":"message_start","message":{"content":[]}}

        event: ping
        data: {"type":"ping"}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hi"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        event: message_stop
        data: {"type":"message_stop"}

        """

        let events = try await normalizedEvents(
            provider: .anthropicMessages,
            chunks: split(Data(fixture.utf8), every: 5)
        )

        XCTAssertEqual(events.first, .started)
        XCTAssertTrue(events.contains(.textDelta("Hi")))
        XCTAssertEqual(events.last, .completed)
    }

    func testAnthropicStreamPreservesIncompleteStopReason() async throws {
        let fixture = """
        event: message_start
        data: {"type":"message_start","message":{"content":[]}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}

        event: message_stop
        data: {"type":"message_stop"}

        """

        let events = try await normalizedEvents(
            provider: .anthropicMessages,
            chunks: split(Data(fixture.utf8), every: 5)
        )

        XCTAssertEqual(events.first, .started)
        XCTAssertEqual(events.last, .incomplete(reason: "max_tokens"))
        XCTAssertFalse(events.contains(.completed))
    }

    func testAnthropicStreamRefusalRequiresDiscardingPartialText() async throws {
        let fixture = """
        event: message_start
        data: {"type":"message_start","message":{"content":[]}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Partial"}}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}

        event: message_stop
        data: {"type":"message_stop"}

        """

        let events = try await normalizedEvents(
            provider: .anthropicMessages,
            chunks: split(Data(fixture.utf8), every: 5)
        )

        XCTAssertTrue(events.contains(.textDelta("Partial")))
        XCTAssertTrue(events.contains(.discardedText(reason: "refusal")))
        XCTAssertEqual(events.last, .refused)
        XCTAssertFalse(events.contains(.completed))
    }

    func testOpenRouterWaitsForDoneMarker() async throws {
        let fixture = """
        : OPENROUTER PROCESSING

        data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":"stop"}]}

        data: {"choices":[],"usage":{"total_tokens":2}}

        data: [DONE]

        """

        let events = try await normalizedEvents(
            provider: .openRouterChat,
            chunks: split(Data(fixture.utf8), every: 3)
        )

        XCTAssertEqual(events.filter { $0 == .completed }.count, 1)
        XCTAssertEqual(events.last, .completed)
        XCTAssertTrue(events.contains(.textDelta("Hi")))
    }

    func testOpenRouterStreamingChoiceErrorIsRejected() async throws {
        let fixture = """
        data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"error","error":{"message":"provider failed"}}]}

        data: [DONE]

        """

        do {
            _ = try await normalizedEvents(
                provider: .openRouterChat,
                chunks: split(Data(fixture.utf8), every: 4)
            )
            XCTFail("Expected the embedded OpenRouter stream error to be rejected.")
        } catch let error as PackagisError {
            XCTAssertEqual(error, .providerError("provider failed"))
        }
    }

    func testOpenRouterStreamPreservesLengthFinishReason() async throws {
        let fixture = """
        data: {"choices":[{"delta":{"content":"Partial"},"finish_reason":"length"}]}

        data: {"choices":[],"usage":{"total_tokens":8}}

        data: [DONE]

        """

        let events = try await normalizedEvents(
            provider: .openRouterChat,
            chunks: split(Data(fixture.utf8), every: 4)
        )

        XCTAssertEqual(events.first, .textDelta("Partial"))
        XCTAssertTrue(events.contains { event in
            if case .providerEvent = event {
                return true
            }
            return false
        })
        XCTAssertEqual(events.last, .incomplete(reason: "length"))
    }

    func testStreamingHTTPErrorIncludesProviderMessage() async throws {
        let transport = MockTransport(replies: [
            .stream(
                statusCode: 401,
                headers: ["Content-Type": "application/json"],
                chunks: [Data(#"{"error":{"message":"invalid key"}}"#.utf8)]
            ),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openRouterChat,
                modelID: "openai/mock"
            ),
            referenceDate: fixedDate()
        )

        do {
            _ = try await client.stream(prepared)
            XCTFail("Expected the streaming HTTP error to be rejected.")
        } catch let error as PackagisError {
            XCTAssertEqual(error, .httpStatus(401, message: "invalid key"))
        }
    }

    func testDisallowedCredentialHeaderIsRejected() async throws {
        let transport = MockTransport(replies: [])
        let credentials = ClosureCredentialProvider { _ in
            ["X-Forwarded-For": "203.0.113.1"]
        }
        let client = PackagisClient(
            transport: transport,
            credentials: credentials
        )
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openAIResponses,
                modelID: "mock-openai"
            ),
            referenceDate: fixedDate()
        )

        do {
            _ = try await client.send(prepared)
            XCTFail("Expected credential header validation to fail.")
        } catch let error as PackagisError {
            XCTAssertEqual(error, .invalidCredentialHeader("X-Forwarded-For"))
        }
    }

    private func normalizedEvents(
        provider: ProviderID,
        chunks: [Data]
    ) async throws -> [ModelStreamEvent] {
        let transport = MockTransport(replies: [
            .stream(chunks: chunks),
        ])
        let client = PackagisClient(transport: transport)
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: provider,
                modelID: "mock-model"
            ),
            referenceDate: fixedDate()
        )

        var events: [ModelStreamEvent] = []
        let stream = try await client.stream(prepared)
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func split(_ data: Data, every size: Int) -> [Data] {
        stride(from: 0, to: data.count, by: size).map { start in
            let end = min(start + size, data.count)
            return Data(data[start ..< end])
        }
    }
}

private actor StreamTerminationProbe {
    private var terminated = false

    func markTerminated() {
        terminated = true
    }

    func didTerminate() -> Bool {
        terminated
    }
}

private final class HangingStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let probe: StreamTerminationProbe

    init(probe: StreamTerminationProbe) {
        self.probe = probe
    }

    func makeBody() -> HTTPBodyStream {
        HTTPBodyStream(
            AsyncThrowingStream { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                continuation.onTermination = { [probe] _ in
                    Task {
                        await probe.markTerminated()
                    }
                }
                continuation.yield(
                    Data(
                        "event: response.created\n"
                            .appending(
                                #"data: {"type":"response.created"}"#
                            )
                            .appending("\n\n")
                            .utf8
                    )
                )
            }
        )
    }
}

private struct CancellationProbeTransport: HTTPTransport {
    let state: HangingStreamState

    func execute(_: HTTPRequest) async throws -> HTTPResponse {
        throw PackagisError.wrongMockReplyKind
    }

    func openStream(_: HTTPRequest) async throws -> HTTPStreamResponse {
        HTTPStreamResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/event-stream"],
            body: state.makeBody()
        )
    }
}
