import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case openAIResponses
    case anthropicMessages
    case openRouterChat
}

public enum AnthropicWebSearchTool: String, Codable, Sendable {
    case basic = "web_search_20250305"
    case dynamicFiltering = "web_search_20260209"
    case responseInclusion = "web_search_20260318"
}

public struct OpenRouterAttribution: Equatable, Sendable {
    public var referer: URL?
    public var title: String?

    public init(referer: URL? = nil, title: String? = nil) {
        self.referer = referer
        self.title = title
    }
}

public struct ProviderTarget: Equatable, Sendable {
    public var provider: ProviderID
    public var modelID: String
    public var endpoint: URL
    public var anthropicWebSearchTool: AnthropicWebSearchTool
    public var openRouterAttribution: OpenRouterAttribution?

    public var anthropicVersion: String {
        "2023-06-01"
    }

    public init(
        provider: ProviderID,
        modelID: String,
        endpoint: URL? = nil,
        anthropicWebSearchTool: AnthropicWebSearchTool = .basic,
        openRouterAttribution: OpenRouterAttribution? = nil
    ) {
        self.provider = provider
        self.modelID = modelID
        self.endpoint = endpoint ?? provider.defaultEndpoint
        self.anthropicWebSearchTool = anthropicWebSearchTool
        self.openRouterAttribution = openRouterAttribution
    }
}

extension ProviderID {
    var defaultEndpoint: URL {
        switch self {
        case .openAIResponses:
            URL(string: "https://api.openai.com/v1/responses")!
        case .anthropicMessages:
            URL(string: "https://api.anthropic.com/v1/messages")!
        case .openRouterChat:
            URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        }
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct ModelMessage: Codable, Equatable, Sendable {
    public var role: MessageRole
    public var content: String

    public init(role: MessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ModelRequest: Equatable, Sendable {
    public var instructions: String?
    public var messages: [ModelMessage]
    public var maxOutputTokens: Int?
    public var webSearchEnabled: Bool
    public var stableUserIdentifier: String?

    public init(
        instructions: String? = nil,
        messages: [ModelMessage],
        maxOutputTokens: Int? = nil,
        webSearchEnabled: Bool = false,
        stableUserIdentifier: String? = nil
    ) {
        self.instructions = instructions
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.webSearchEnabled = webSearchEnabled
        self.stableUserIdentifier = stableUserIdentifier
    }
}

public enum DeliveryMode: String, Sendable {
    case single
    case streaming
}

public enum EnvironmentDelivery: String, Codable, Sendable {
    case semantic
    case native
    case transport
    case omitted
}

public enum EnvironmentStatus: String, Codable, Sendable {
    case applied
    case providerDependent
    case unsupported
    case notRequested
}

public struct EnvironmentReportEntry: Codable, Equatable, Sendable {
    public var dimension: String
    public var requestedValue: String
    public var delivery: EnvironmentDelivery
    public var status: EnvironmentStatus
    public var detail: String

    public init(
        dimension: String,
        requestedValue: String,
        delivery: EnvironmentDelivery,
        status: EnvironmentStatus,
        detail: String
    ) {
        self.dimension = dimension
        self.requestedValue = requestedValue
        self.delivery = delivery
        self.status = status
        self.detail = detail
    }
}

public struct PreparationReport: Codable, Equatable, Sendable {
    public var profileID: String
    public var provider: ProviderID
    public var entries: [EnvironmentReportEntry]

    public init(
        profileID: String,
        provider: ProviderID,
        entries: [EnvironmentReportEntry]
    ) {
        self.profileID = profileID
        self.provider = provider
        self.entries = entries
    }
}

public struct HTTPRequest: Equatable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data

    public init(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct ModelResponse: Sendable {
    public var text: String
    public var completion: ModelCompletionStatus
    public var statusCode: Int
    public var headers: [String: String]
    public var rawBody: Data
    public var report: PreparationReport

    public init(
        text: String,
        completion: ModelCompletionStatus = .completed,
        statusCode: Int,
        headers: [String: String],
        rawBody: Data,
        report: PreparationReport
    ) {
        self.text = text
        self.completion = completion
        self.statusCode = statusCode
        self.headers = headers
        self.rawBody = rawBody
        self.report = report
    }
}

public enum ModelCompletionStatus: Equatable, Sendable {
    case completed
    case incomplete(reason: String?)
    case refused
}

public struct SSEEvent: Equatable, Sendable {
    public var name: String?
    public var data: String
    public var id: String?
    public var retryMilliseconds: Int?

    public init(
        name: String? = nil,
        data: String,
        id: String? = nil,
        retryMilliseconds: Int? = nil
    ) {
        self.name = name
        self.data = data
        self.id = id
        self.retryMilliseconds = retryMilliseconds
    }
}

public enum ModelStreamEvent: Equatable, Sendable {
    case started
    case textDelta(String)
    case discardedText(reason: String)
    case completed
    case incomplete(reason: String?)
    case refused
    case providerEvent(SSEEvent)
}
