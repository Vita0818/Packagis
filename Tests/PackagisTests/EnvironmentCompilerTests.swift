import Foundation
import XCTest
@testable import Packagis

final class EnvironmentCompilerTests: XCTestCase {
    func testOpenAIEnvironmentAndSearchLocationMapping() throws {
        let client = PackagisClient(transport: MockTransport())
        let target = ProviderTarget(
            provider: .openAIResponses,
            modelID: "mock-openai"
        )
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(
                privacy: .init(storage: .disabled)
            ),
            target: target,
            referenceDate: fixedDate()
        )

        let preview = try prepared.preview(for: .single)
        let body = try jsonObject(preview.request.body)

        XCTAssertEqual(body["model"] as? String, "mock-openai")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["safety_identifier"] as? String, "stable-user-001")

        let instructions = try XCTUnwrap(body["instructions"] as? String)
        XCTAssertTrue(instructions.contains("en-US"))
        XCTAssertTrue(instructions.contains("America/New_York"))
        XCTAssertTrue(instructions.contains("Be concise."))
        XCTAssertEqual(instructions.components(separatedBy: "Regional response preferences:").count, 2)

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let location = try XCTUnwrap(tools.first?["user_location"] as? [String: Any])
        XCTAssertEqual(location["type"] as? String, "approximate")
        XCTAssertEqual(location["country"] as? String, "US")
        XCTAssertEqual(location["city"] as? String, "New York")
        XCTAssertEqual(location["timezone"] as? String, "America/New_York")

        XCTAssertNil(preview.request.headers["Authorization"])
        XCTAssertNil(preview.request.headers["x-api-key"])
    }

    func testProfileSwitchDoesNotChangeStableIdentity() throws {
        let client = PackagisClient(transport: MockTransport())
        let target = ProviderTarget(
            provider: .openAIResponses,
            modelID: "mock-openai"
        )
        let request = makeRequest()

        let first = try client.prepare(
            request,
            profile: makeProfile(),
            target: target,
            referenceDate: fixedDate()
        )
        let second = try client.prepare(
            request,
            profile: makeProfile(
                id: "ja-tokyo",
                languageTag: "ja-JP",
                timeZoneIdentifier: "Asia/Tokyo",
                countryCode: "JP",
                region: "Tokyo",
                city: "Tokyo"
            ),
            target: target,
            referenceDate: fixedDate()
        )

        let firstBody = try jsonObject(first.preview(for: .single).request.body)
        let secondBody = try jsonObject(second.preview(for: .single).request.body)

        XCTAssertEqual(
            firstBody["safety_identifier"] as? String,
            secondBody["safety_identifier"] as? String
        )
    }

    func testPreparationIsDeterministicForSameInputs() throws {
        let client = PackagisClient(transport: MockTransport())
        let target = ProviderTarget(
            provider: .openAIResponses,
            modelID: "mock-openai"
        )

        let first = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: target,
            referenceDate: fixedDate()
        )
        let second = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: target,
            referenceDate: fixedDate()
        )

        XCTAssertEqual(
            try first.preview(for: .single),
            try second.preview(for: .single)
        )
        XCTAssertEqual(first.report, second.report)
    }

    func testOpenRouterSearchLocationIsReportedAsProviderDependent() throws {
        let client = PackagisClient(transport: MockTransport())
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openRouterChat,
                modelID: "unknown/mock-model"
            ),
            referenceDate: fixedDate()
        )

        let searchLocation = try XCTUnwrap(
            prepared.report.entries.first { $0.dimension == "search_location" }
        )
        XCTAssertEqual(searchLocation.delivery, .native)
        XCTAssertEqual(searchLocation.status, .providerDependent)
        XCTAssertTrue(searchLocation.detail.contains("may fall back"))
    }

    func testInvalidTimeZoneIsRejected() {
        let client = PackagisClient(transport: MockTransport())
        let profile = makeProfile(timeZoneIdentifier: "Mars/Olympus")

        XCTAssertThrowsError(
            try client.prepare(
                makeRequest(),
                profile: profile,
                target: ProviderTarget(
                    provider: .openAIResponses,
                    modelID: "mock-openai"
                ),
                referenceDate: fixedDate()
            )
        )
    }

    func testNonOfficialEndpointIsRejected() {
        let client = PackagisClient(transport: MockTransport())

        XCTAssertThrowsError(
            try client.prepare(
                makeRequest(),
                profile: makeProfile(),
                target: ProviderTarget(
                    provider: .openAIResponses,
                    modelID: "mock-openai",
                    endpoint: URL(string: "https://example.invalid/v1/responses")
                ),
                referenceDate: fixedDate()
            )
        )
    }

    func testControlCharactersInOpenRouterTitleAreRejected() {
        let client = PackagisClient(transport: MockTransport())

        XCTAssertThrowsError(
            try client.prepare(
                makeRequest(),
                profile: makeProfile(),
                target: ProviderTarget(
                    provider: .openRouterChat,
                    modelID: "openai/mock",
                    openRouterAttribution: .init(title: "Packagis\r\nInjected: true")
                ),
                referenceDate: fixedDate()
            )
        )
    }

    func testControlCharactersInCityAreRejected() {
        let client = PackagisClient(transport: MockTransport())
        let profile = makeProfile(city: "New York\r\nX-Test: injected")

        XCTAssertThrowsError(
            try client.prepare(
                makeRequest(),
                profile: profile,
                target: ProviderTarget(
                    provider: .openAIResponses,
                    modelID: "mock-openai"
                ),
                referenceDate: fixedDate()
            )
        )
    }
}
