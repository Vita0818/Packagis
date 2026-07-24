import Foundation
import Packagis

@main
struct PackagisPrototype {
    static func main() async throws {
        let mockResponse = Data(
            """
            {
              "output_text": "Mock provider response in English."
            }
            """.utf8
        )

        let mockStream = """
        event: response.created
        data: {"type":"response.created"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hello "}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"from the mock stream."}

        event: response.completed
        data: {"type":"response.completed"}

        """

        let transport = MockTransport(replies: [
            .response(
                HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: mockResponse
                )
            ),
            .stream(chunks: split(Data(mockStream.utf8), at: 47)),
        ])

        let client = PackagisClient(transport: transport)
        let profile = EnvironmentProfile(
            id: "us-new-york-en",
            response: ResponsePreferences(
                languageTag: "en-US",
                timeZoneIdentifier: "America/New_York",
                spelling: .american,
                dateOrder: .monthDayYear,
                timeCycle: .twelveHour,
                currencyCode: "USD",
                unitSystem: .us
            ),
            location: ApproximateLocation(
                countryCode: "US",
                region: "New York",
                city: "New York"
            ),
            privacy: PrivacyPreferences(storage: .disabled)
        )
        let target = ProviderTarget(
            provider: .openAIResponses,
            modelID: "mock-model"
        )
        let request = ModelRequest(
            messages: [
                ModelMessage(
                    role: .user,
                    content: "What is happening nearby?"
                ),
            ],
            maxOutputTokens: 256,
            webSearchEnabled: true,
            stableUserIdentifier: "mock-user-001"
        )
        let referenceDate = Date(timeIntervalSince1970: 1_774_262_400)
        let prepared = try client.prepare(
            request,
            profile: profile,
            target: target,
            referenceDate: referenceDate
        )

        let preview = try prepared.preview(for: .single)
        print("Prepared request (contains no credentials):")
        print(prettyJSON(preview.request.body))

        let response = try await client.send(prepared)
        print("\nNormalized response:")
        print(response.text)

        print("\nNormalized stream:")
        let stream = try await client.stream(prepared)
        for try await event in stream {
            switch event {
            case .started:
                print("[started]")
            case let .textDelta(text):
                print(text, terminator: "")
            case let .discardedText(reason):
                print("\n[discard prior text: \(reason)]")
            case .completed:
                print("\n[completed]")
            case let .incomplete(reason):
                print("\n[incomplete: \(reason ?? "unspecified")]")
            case .refused:
                print("\n[refused]")
            case .providerEvent:
                break
            }
        }
    }

    private static func split(_ data: Data, at index: Int) -> [Data] {
        guard index > 0, index < data.count else {
            return [data]
        }
        return [
            Data(data.prefix(index)),
            Data(data.dropFirst(index)),
        ]
    }

    private static func prettyJSON(_ data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            )
        else {
            return String(decoding: data, as: UTF8.self)
        }

        return String(decoding: pretty, as: UTF8.self)
    }
}
