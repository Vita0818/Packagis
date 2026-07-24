import Foundation

struct CompiledEnvironment: Sendable {
    var semanticInstructions: String
    var nativeLocation: JSONValue
    var reportEntries: [EnvironmentReportEntry]
}

enum EnvironmentCompiler {
    static func compile(
        profile: EnvironmentProfile,
        request: ModelRequest,
        target: ProviderTarget,
        referenceDate: Date
    ) throws -> CompiledEnvironment {
        try EnvironmentProfileValidator.validate(profile)
        try validate(request: request, target: target)

        guard let timeZone = TimeZone(identifier: profile.response.timeZoneIdentifier) else {
            throw PackagisError.invalidProfile(
                "Unknown IANA time zone \(profile.response.timeZoneIdentifier)."
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = timeZone

        var lines = [
            "Regional response preferences:",
            "- Default response language: \(profile.response.languageTag).",
            "- Interpret otherwise-unqualified dates and times in \(profile.response.timeZoneIdentifier).",
            "- Current local datetime: \(formatter.string(from: referenceDate)) (\(profile.response.timeZoneIdentifier)).",
        ]

        if let spelling = profile.response.spelling {
            lines.append("- Use \(spelling.rawValue) spelling.")
        }

        if let dateOrder = profile.response.dateOrder {
            lines.append("- Preferred date order: \(dateOrder.instructionValue).")
        }

        if let timeCycle = profile.response.timeCycle {
            lines.append("- Preferred time cycle: \(timeCycle.instructionValue).")
        }

        if let currencyCode = profile.response.currencyCode {
            lines.append("- Preferred currency display: \(currencyCode.uppercased()).")
        }

        if let unitSystem = profile.response.unitSystem {
            lines.append("- Preferred measurement system: \(unitSystem.instructionValue).")
        }

        lines.append(
            "- An explicit user request for another response language overrides the default language."
        )
        lines.append(
            "- Do not infer residency, citizenship, legal jurisdiction, or account region from these preferences."
        )

        var location: [String: JSONValue] = [
            "type": .string("approximate"),
            "timezone": .string(profile.response.timeZoneIdentifier),
        ]

        if let countryCode = profile.location?.countryCode {
            location["country"] = .string(countryCode.uppercased())
        }

        if let region = profile.location?.region {
            location["region"] = .string(region)
        }

        if let city = profile.location?.city {
            location["city"] = .string(city)
        }

        var reportEntries = [
            EnvironmentReportEntry(
                dimension: "response_language",
                requestedValue: profile.response.languageTag,
                delivery: .semantic,
                status: .applied,
                detail: "Injected through the provider's high-priority instruction surface."
            ),
            EnvironmentReportEntry(
                dimension: "timezone",
                requestedValue: profile.response.timeZoneIdentifier,
                delivery: .semantic,
                status: .applied,
                detail: "Used for semantic context and the request-local current datetime."
            ),
        ]

        if request.webSearchEnabled {
            let searchStatus: EnvironmentStatus =
                target.provider == .openRouterChat ? .providerDependent : .applied
            reportEntries.append(
                EnvironmentReportEntry(
                    dimension: "search_location",
                    requestedValue: displayLocation(profile),
                    delivery: .native,
                    status: searchStatus,
                    detail: target.provider.searchLocationDetail
                )
            )
        } else {
            reportEntries.append(
                EnvironmentReportEntry(
                    dimension: "search_location",
                    requestedValue: displayLocation(profile),
                    delivery: .omitted,
                    status: .notRequested,
                    detail: "Web search is disabled for this request."
                )
            )
        }

        return CompiledEnvironment(
            semanticInstructions: lines.joined(separator: "\n"),
            nativeLocation: .object(location),
            reportEntries: reportEntries
        )
    }

    private static func validate(
        request: ModelRequest,
        target: ProviderTarget
    ) throws {
        let officialEndpoint = target.provider.defaultEndpoint
        guard
            target.endpoint.scheme?.lowercased() == "https",
            let targetHost = target.endpoint.host,
            let officialHost = officialEndpoint.host,
            targetHost.caseInsensitiveCompare(officialHost) == .orderedSame,
            (target.endpoint.port ?? 443) == (officialEndpoint.port ?? 443),
            target.endpoint.user == nil,
            target.endpoint.password == nil,
            target.endpoint.query == nil,
            target.endpoint.fragment == nil
        else {
            throw PackagisError.invalidRequest(
                "Endpoint must use the provider's official HTTPS origin without credentials, query, or fragment."
            )
        }

        guard !target.modelID.isEmpty, target.modelID.count <= 256 else {
            throw PackagisError.invalidRequest("Model ID must contain 1...256 characters.")
        }

        guard !target.modelID.unicodeScalars.contains(
            where: { CharacterSet.controlCharacters.contains($0) }
        ) else {
            throw PackagisError.invalidRequest("Model ID must not contain control characters.")
        }

        guard !request.messages.isEmpty else {
            throw PackagisError.invalidRequest("At least one message is required.")
        }

        if let maxOutputTokens = request.maxOutputTokens, maxOutputTokens <= 0 {
            throw PackagisError.invalidRequest("maxOutputTokens must be greater than zero.")
        }

        if let stableUserIdentifier = request.stableUserIdentifier {
            guard
                !stableUserIdentifier.isEmpty,
                stableUserIdentifier.count <= 64,
                !stableUserIdentifier.unicodeScalars.contains(
                    where: { CharacterSet.controlCharacters.contains($0) }
                )
            else {
                throw PackagisError.invalidRequest(
                    "stableUserIdentifier must contain 1...64 non-control characters."
                )
            }
        }

        if let attribution = target.openRouterAttribution {
            if let title = attribution.title {
                guard
                    !title.isEmpty,
                    title.count <= 256,
                    !title.unicodeScalars.contains(
                        where: { CharacterSet.controlCharacters.contains($0) }
                    )
                else {
                    throw PackagisError.invalidRequest(
                        "OpenRouter attribution title must contain 1...256 non-control characters."
                    )
                }
            }

            if let referer = attribution.referer {
                guard
                    ["http", "https"].contains(referer.scheme?.lowercased() ?? ""),
                    referer.host != nil,
                    referer.user == nil,
                    referer.password == nil,
                    !referer.absoluteString.unicodeScalars.contains(
                        where: { CharacterSet.controlCharacters.contains($0) }
                    )
                else {
                    throw PackagisError.invalidRequest(
                        "OpenRouter attribution referer must be an HTTP(S) URL without embedded credentials."
                    )
                }
            }
        }
    }

    private static func displayLocation(_ profile: EnvironmentProfile) -> String {
        var components = [
            profile.location?.city,
            profile.location?.region,
            profile.location?.countryCode?.uppercased(),
            profile.response.timeZoneIdentifier,
        ].compactMap { $0 }

        if components.isEmpty {
            components.append(profile.response.timeZoneIdentifier)
        }

        return components.joined(separator: ", ")
    }
}

private extension DateOrder {
    var instructionValue: String {
        switch self {
        case .monthDayYear:
            "month/day/year"
        case .dayMonthYear:
            "day/month/year"
        case .yearMonthDay:
            "year/month/day"
        }
    }
}

private extension TimeCycle {
    var instructionValue: String {
        switch self {
        case .twelveHour:
            "12-hour"
        case .twentyFourHour:
            "24-hour"
        }
    }
}

private extension UnitSystem {
    var instructionValue: String {
        switch self {
        case .metric:
            "metric"
        case .us:
            "US customary"
        case .uk:
            "UK mixed"
        }
    }
}

private extension ProviderID {
    var searchLocationDetail: String {
        switch self {
        case .openAIResponses:
            "Mapped to tools[].user_location for OpenAI Web Search."
        case .anthropicMessages:
            "Mapped to the Anthropic web_search tool's user_location."
        case .openRouterChat:
            """
            Mapped to openrouter:web_search parameters.user_location with native search requested; \
            the provider may fall back to a search engine that ignores this location.
            """
        }
    }
}
