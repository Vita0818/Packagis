import Foundation
import XCTest
@testable import Packagis

final class SSEParserTests: XCTestCase {
    func testParserProducesSameEventAcrossEveryByteSplit() throws {
        let fixture = Data(
            """
            : heartbeat\r
            event: response.output_text.delta\r
            id: 42\r
            data: {"type":"response.output_text.delta",\r
            data: "delta":"你"}\r
            \r
            """.utf8
        )
        let expected = SSEEvent(
            name: "response.output_text.delta",
            data: """
            {"type":"response.output_text.delta",
            "delta":"你"}
            """,
            id: "42"
        )

        for chunks in splitAtEveryByte(fixture) {
            var parser = SSEParser()
            var events: [SSEEvent] = []
            for chunk in chunks {
                events.append(contentsOf: try parser.feed(chunk))
            }
            events.append(contentsOf: try parser.finish())
            XCTAssertEqual(events, [expected])
        }
    }

    func testParserHandlesBOMCommentsAndMissingFinalBlankLine() throws {
        var fixture = Data([0xEF, 0xBB, 0xBF])
        fixture.append(
            Data(
                """
                : OPENROUTER PROCESSING
                data: [DONE]
                """.utf8
            )
        )

        var parser = SSEParser()
        let initial = try parser.feed(fixture)
        let final = try parser.finish()

        XCTAssertTrue(initial.isEmpty)
        XCTAssertEqual(final, [SSEEvent(data: "[DONE]")])
    }

    func testParserLimitsEmptyDataLinesWithinOneEvent() throws {
        var parser = SSEParser(maximumEventLines: 2)
        let fixture = Data(
            """
            data:
            data:
            data:

            """.utf8
        )

        XCTAssertThrowsError(try parser.feed(fixture)) { error in
            XCTAssertEqual(error as? PackagisError, .SSELimitExceeded)
        }
    }

    func testCROnlyBlankLineDispatchesWithoutWaitingForAnotherByte() throws {
        var parser = SSEParser()
        let events = try parser.feed(Data("data: immediate\r\r".utf8))

        XCTAssertEqual(events, [SSEEvent(data: "immediate")])
    }

    func testSplitCRLFIgnoresTheOptionalLineFeed() throws {
        var parser = SSEParser()
        let first = try parser.feed(Data("data: one\r".utf8))
        let second = try parser.feed(Data("\n\r".utf8))
        let third = try parser.feed(Data("\ndata: two\r\r".utf8))

        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second, [SSEEvent(data: "one")])
        XCTAssertEqual(third, [SSEEvent(data: "two")])
    }
}
