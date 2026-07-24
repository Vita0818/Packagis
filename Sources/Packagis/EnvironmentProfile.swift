import Foundation

public struct EnvironmentProfile: Codable, Equatable, Sendable {
    public var id: String
    public var response: ResponsePreferences
    public var location: ApproximateLocation?
    public var privacy: PrivacyPreferences

    public init(
        id: String,
        response: ResponsePreferences,
        location: ApproximateLocation? = nil,
        privacy: PrivacyPreferences = .init()
    ) {
        self.id = id
        self.response = response
        self.location = location
        self.privacy = privacy
    }
}

public struct ResponsePreferences: Codable, Equatable, Sendable {
    public var languageTag: String
    public var timeZoneIdentifier: String
    public var spelling: SpellingPreference?
    public var dateOrder: DateOrder?
    public var timeCycle: TimeCycle?
    public var currencyCode: String?
    public var unitSystem: UnitSystem?

    public init(
        languageTag: String,
        timeZoneIdentifier: String,
        spelling: SpellingPreference? = nil,
        dateOrder: DateOrder? = nil,
        timeCycle: TimeCycle? = nil,
        currencyCode: String? = nil,
        unitSystem: UnitSystem? = nil
    ) {
        self.languageTag = languageTag
        self.timeZoneIdentifier = timeZoneIdentifier
        self.spelling = spelling
        self.dateOrder = dateOrder
        self.timeCycle = timeCycle
        self.currencyCode = currencyCode
        self.unitSystem = unitSystem
    }
}

public struct ApproximateLocation: Codable, Equatable, Sendable {
    public var countryCode: String?
    public var region: String?
    public var city: String?

    public init(
        countryCode: String? = nil,
        region: String? = nil,
        city: String? = nil
    ) {
        self.countryCode = countryCode
        self.region = region
        self.city = city
    }
}

public struct PrivacyPreferences: Codable, Equatable, Sendable {
    public var storage: StoragePreference
    public var dataCollection: DataCollectionPreference
    public var requireZeroDataRetention: Bool

    public init(
        storage: StoragePreference = .providerDefault,
        dataCollection: DataCollectionPreference = .providerDefault,
        requireZeroDataRetention: Bool = false
    ) {
        self.storage = storage
        self.dataCollection = dataCollection
        self.requireZeroDataRetention = requireZeroDataRetention
    }
}

public enum SpellingPreference: String, Codable, Sendable {
    case american
    case british
}

public enum DateOrder: String, Codable, Sendable {
    case monthDayYear
    case dayMonthYear
    case yearMonthDay
}

public enum TimeCycle: String, Codable, Sendable {
    case twelveHour
    case twentyFourHour
}

public enum UnitSystem: String, Codable, Sendable {
    case metric
    case us
    case uk
}

public enum StoragePreference: String, Codable, Sendable {
    case providerDefault
    case disabled
    case enabled
}

public enum DataCollectionPreference: String, Codable, Sendable {
    case providerDefault
    case deny
    case allow
}

enum EnvironmentProfileValidator {
    static func validate(_ profile: EnvironmentProfile) throws {
        try validateSafeText(profile.id, field: "profile id", maximumLength: 128)
        try validateLanguageTag(profile.response.languageTag)

        guard TimeZone(identifier: profile.response.timeZoneIdentifier) != nil else {
            throw PackagisError.invalidProfile(
                "Unknown IANA time zone \(profile.response.timeZoneIdentifier)."
            )
        }

        if let currencyCode = profile.response.currencyCode {
            let normalized = currencyCode.uppercased()
            guard normalized.count == 3, normalized.allSatisfy(\.isLetter) else {
                throw PackagisError.invalidProfile(
                    "Currency must be a three-letter ISO 4217 code."
                )
            }
        }

        if let location = profile.location {
            if let countryCode = location.countryCode {
                let normalized = countryCode.uppercased()
                guard normalized.count == 2, normalized.allSatisfy(\.isLetter) else {
                    throw PackagisError.invalidProfile(
                        "Country must be a two-letter ISO 3166-1 alpha-2 code."
                    )
                }
            }

            if let region = location.region {
                try validateSafeText(region, field: "region", maximumLength: 128)
            }

            if let city = location.city {
                try validateSafeText(city, field: "city", maximumLength: 128)
            }

            guard location.countryCode != nil || location.region != nil || location.city != nil else {
                throw PackagisError.invalidProfile(
                    "Approximate location must contain country, region, or city."
                )
            }
        }
    }

    private static func validateLanguageTag(_ languageTag: String) throws {
        let parts = languageTag.split(separator: "-", omittingEmptySubsequences: false)
        guard
            languageTag.count <= 64,
            !parts.isEmpty,
            parts.allSatisfy({ !$0.isEmpty }),
            (2 ... 3).contains(parts[0].count),
            parts[0].allSatisfy(\.isLetter),
            parts.dropFirst().allSatisfy({
                (2 ... 8).contains($0.count)
                    && $0.allSatisfy { $0.isLetter || $0.isNumber }
            })
        else {
            throw PackagisError.invalidProfile(
                "Language must be a structurally valid BCP 47 tag."
            )
        }
    }

    private static func validateSafeText(
        _ value: String,
        field: String,
        maximumLength: Int
    ) throws {
        guard !value.isEmpty, value.count <= maximumLength else {
            throw PackagisError.invalidProfile(
                "\(field) must contain 1...\(maximumLength) characters."
            )
        }

        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw PackagisError.invalidProfile(
                "\(field) must not contain control characters."
            )
        }
    }
}
