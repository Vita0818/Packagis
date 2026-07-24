import Foundation
@testable import Packagis

func makeProfile(
    id: String = "us-new-york-en",
    languageTag: String = "en-US",
    timeZoneIdentifier: String = "America/New_York",
    countryCode: String? = "US",
    region: String? = "New York",
    city: String? = "New York",
    privacy: PrivacyPreferences = .init()
) -> EnvironmentProfile {
    EnvironmentProfile(
        id: id,
        response: ResponsePreferences(
            languageTag: languageTag,
            timeZoneIdentifier: timeZoneIdentifier,
            spelling: .american,
            dateOrder: .monthDayYear,
            timeCycle: .twelveHour,
            currencyCode: "USD",
            unitSystem: .us
        ),
        location: ApproximateLocation(
            countryCode: countryCode,
            region: region,
            city: city
        ),
        privacy: privacy
    )
}

func makeRequest(webSearch: Bool = true) -> ModelRequest {
    ModelRequest(
        instructions: "Be concise.",
        messages: [
            ModelMessage(role: .user, content: "What is happening nearby?"),
        ],
        maxOutputTokens: 256,
        webSearchEnabled: webSearch,
        stableUserIdentifier: "stable-user-001"
    )
}

func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_774_262_400)
}

func jsonObject(_ data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrapObject(object as? [String: Any])
}

private func XCTUnwrapObject<T>(
    _ value: T?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let value else {
        throw TestSupportError.unwrapFailed(file: "\(file)", line: line)
    }
    return value
}

private enum TestSupportError: Error {
    case unwrapFailed(file: String, line: UInt)
}

func splitAtEveryByte(_ data: Data) -> [[Data]] {
    guard data.count > 1 else {
        return [[data]]
    }

    return (1 ..< data.count).map { index in
        [
            Data(data.prefix(index)),
            Data(data.dropFirst(index)),
        ]
    }
}
