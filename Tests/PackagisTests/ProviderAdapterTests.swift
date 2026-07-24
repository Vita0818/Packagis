import Foundation
import XCTest
@testable import Packagis

final class ProviderAdapterTests: XCTestCase {
    func testAnthropicRequestShape() throws {
        let client = PackagisClient(transport: MockTransport())
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .anthropicMessages,
                modelID: "mock-claude"
            ),
            referenceDate: fixedDate()
        )

        let preview = try prepared.preview(for: .streaming)
        let body = try jsonObject(preview.request.body)

        XCTAssertEqual(body["model"] as? String, "mock-claude")
        XCTAssertEqual(body["max_tokens"] as? Int, 256)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNotNil(body["system"] as? String)
        XCTAssertEqual(
            (body["metadata"] as? [String: Any])?["user_id"] as? String,
            "stable-user-001"
        )
        XCTAssertEqual(preview.request.headers["anthropic-version"], "2023-06-01")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "web_search_20250305")
        XCTAssertEqual(tools.first?["name"] as? String, "web_search")
        let location = try XCTUnwrap(tools.first?["user_location"] as? [String: Any])
        XCTAssertEqual(location["country"] as? String, "US")
    }

    func testOpenRouterRequestShapeAndPrivacyRouting() throws {
        let client = PackagisClient(transport: MockTransport())
        let privacy = PrivacyPreferences(
            storage: .disabled,
            dataCollection: .deny,
            requireZeroDataRetention: true
        )
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(privacy: privacy),
            target: ProviderTarget(
                provider: .openRouterChat,
                modelID: "openai/mock",
                openRouterAttribution: OpenRouterAttribution(
                    referer: URL(string: "https://example.invalid"),
                    title: "Packagis Prototype"
                )
            ),
            referenceDate: fixedDate()
        )

        let preview = try prepared.preview(for: .streaming)
        let body = try jsonObject(preview.request.body)

        XCTAssertEqual(body["model"] as? String, "openai/mock")
        XCTAssertEqual(body["max_tokens"] as? Int, 256)
        XCTAssertEqual(body["user"] as? String, "stable-user-001")
        XCTAssertEqual(preview.request.headers["X-OpenRouter-Title"], "Packagis Prototype")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let parameters = try XCTUnwrap(tools.first?["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["engine"] as? String, "native")
        let location = try XCTUnwrap(parameters["user_location"] as? [String: Any])
        XCTAssertEqual(location["timezone"] as? String, "America/New_York")

        let provider = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(provider["require_parameters"] as? Bool, true)
        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["zdr"] as? Bool, true)
        XCTAssertNil(body["store"])
    }

    func testAnthropicDynamicWebSearchDoesNotDisableDynamicFiltering() throws {
        let client = PackagisClient(transport: MockTransport())
        let prepared = try client.prepare(
            makeRequest(),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .anthropicMessages,
                modelID: "mock-claude",
                anthropicWebSearchTool: .dynamicFiltering
            ),
            referenceDate: fixedDate()
        )

        let body = try jsonObject(prepared.preview(for: .single).request.body)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "web_search_20260209")
        XCTAssertNil(tools.first?["allowed_callers"])
    }

    func testWebSearchDisabledOmitsNativeLocation() throws {
        let client = PackagisClient(transport: MockTransport())
        let prepared = try client.prepare(
            makeRequest(webSearch: false),
            profile: makeProfile(),
            target: ProviderTarget(
                provider: .openRouterChat,
                modelID: "openai/mock"
            ),
            referenceDate: fixedDate()
        )

        let body = try jsonObject(prepared.preview(for: .single).request.body)
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["provider"])
    }
}
