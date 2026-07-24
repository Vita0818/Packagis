import Foundation

enum ProviderAdapters {
    static func prepare(
        request: ModelRequest,
        profile: EnvironmentProfile,
        target: ProviderTarget,
        compiledEnvironment: CompiledEnvironment
    ) throws -> PreparedRequest {
        let body: JSONValue
        var headers = [
            "Content-Type": "application/json",
        ]
        var reportEntries = compiledEnvironment.reportEntries

        switch target.provider {
        case .openAIResponses:
            body = openAIResponsesBody(
                request: request,
                profile: profile,
                target: target,
                environment: compiledEnvironment
            )
            appendOpenAIPrivacyReport(profile.privacy, to: &reportEntries)

        case .anthropicMessages:
            headers["anthropic-version"] = target.anthropicVersion
            body = anthropicMessagesBody(
                request: request,
                target: target,
                environment: compiledEnvironment
            )
            appendUnsupportedPrivacyReport(
                profile.privacy,
                providerName: "Anthropic Messages",
                to: &reportEntries
            )

        case .openRouterChat:
            if let referer = target.openRouterAttribution?.referer {
                headers["HTTP-Referer"] = referer.absoluteString
            }
            if let title = target.openRouterAttribution?.title {
                headers["X-OpenRouter-Title"] = title
            }

            body = openRouterChatBody(
                request: request,
                profile: profile,
                target: target,
                environment: compiledEnvironment
            )
            appendOpenRouterPrivacyReport(profile.privacy, to: &reportEntries)
        }

        return PreparedRequest(
            target: target,
            bodyTemplate: body,
            baseHeaders: headers,
            report: PreparationReport(
                profileID: profile.id,
                provider: target.provider,
                entries: reportEntries
            )
        )
    }

    static func decodeResponse(
        provider: ProviderID,
        data: Data
    ) throws -> (text: String, completion: ModelCompletionStatus) {
        let object = try decodeJSONObject(data)

        if containsError(object) || object["status"] as? String == "failed" {
            throw PackagisError.providerError(providerErrorMessage(object))
        }

        switch provider {
        case .openAIResponses:
            let completion: ModelCompletionStatus =
                object["status"] as? String == "incomplete"
                    ? .incomplete(reason: openAIIncompleteReason(object))
                    : .completed

            if let outputText = object["output_text"] as? String {
                return (outputText, completion)
            }

            let output = object["output"] as? [[String: Any]] ?? []
            let textBlocks = output
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .compactMap { $0["text"] as? String }
            let refusalBlocks = output
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .compactMap { $0["refusal"] as? String }

            if !refusalBlocks.isEmpty {
                return (
                    refusalBlocks.joined(),
                    .refused
                )
            }

            if textBlocks.isEmpty, completion.allowsEmptyText {
                return ("", completion)
            }

            guard !textBlocks.isEmpty else {
                throw PackagisError.malformedResponse(
                    "OpenAI response did not contain text output."
                )
            }
            return (textBlocks.joined(), completion)

        case .anthropicMessages:
            guard let stopReason = object["stop_reason"] as? String else {
                throw PackagisError.malformedResponse(
                    "Anthropic response did not contain stop_reason."
                )
            }
            let completion = completionStatus(
                stopReason: stopReason,
                completeReasons: ["end_turn", "stop_sequence"]
            )
            let content = object["content"] as? [[String: Any]] ?? []
            let textBlocks: [String] = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else {
                    return nil
                }
                return block["text"] as? String
            }
            if completion == .refused {
                return ("", .refused)
            }
            return (textBlocks.joined(), completion)

        case .openRouterChat:
            let choices = object["choices"] as? [[String: Any]] ?? []
            guard !choices.isEmpty else {
                throw PackagisError.malformedResponse(
                    "OpenRouter response did not contain choices."
                )
            }
            for choice in choices where openRouterChoiceContainsError(choice) {
                throw PackagisError.providerError(providerErrorMessage(choice))
            }
            let finishReasons = try choices.map { choice -> String in
                guard let reason = choice["finish_reason"] as? String else {
                    throw PackagisError.malformedResponse(
                        "OpenRouter response choice did not contain finish_reason."
                    )
                }
                return reason
            }
            let incompleteReasons = finishReasons.filter { $0 != "stop" }
            let completion: ModelCompletionStatus = incompleteReasons.isEmpty
                ? .completed
                : .incomplete(
                    reason: Array(Set(incompleteReasons)).sorted().joined(separator: ",")
                )
            let textBlocks: [String] = choices.compactMap { choice -> String? in
                let message = choice["message"] as? [String: Any]
                return message?["content"] as? String
            }
            if textBlocks.isEmpty, completion.allowsEmptyText {
                return ("", completion)
            }
            guard !textBlocks.isEmpty else {
                throw PackagisError.malformedResponse(
                    "OpenRouter response did not contain text output."
                )
            }
            return (textBlocks.joined(), completion)
        }
    }

    static func decodeHTTPErrorMessage(_ data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let object = try? decodeJSONObject(data) {
            if containsError(object) || object["message"] is String {
                return providerErrorMessage(object)
            }
        }

        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return String(value.prefix(1_024))
    }

    static func decodeStreamEvent(
        provider: ProviderID,
        event: SSEEvent,
        pendingCompletion: inout ModelCompletionStatus?
    ) throws -> [ModelStreamEvent] {
        switch provider {
        case .openAIResponses:
            try decodeOpenAIStreamEvent(
                event,
                pendingCompletion: &pendingCompletion
            )
        case .anthropicMessages:
            try decodeAnthropicStreamEvent(
                event,
                pendingCompletion: &pendingCompletion
            )
        case .openRouterChat:
            try decodeOpenRouterStreamEvent(
                event,
                pendingCompletion: &pendingCompletion
            )
        }
    }

    private static func openAIResponsesBody(
        request: ModelRequest,
        profile: EnvironmentProfile,
        target: ProviderTarget,
        environment: CompiledEnvironment
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(target.modelID),
            "input": messageArray(request.messages),
        ]

        object["instructions"] = .string(
            combinedInstructions(request.instructions, environment.semanticInstructions)
        )

        if let maxOutputTokens = request.maxOutputTokens {
            object["max_output_tokens"] = .integer(maxOutputTokens)
        }

        if request.webSearchEnabled {
            object["tools"] = .array([
                .object([
                    "type": .string("web_search"),
                    "user_location": environment.nativeLocation,
                ]),
            ])
        }

        if let stableUserIdentifier = request.stableUserIdentifier {
            object["safety_identifier"] = .string(stableUserIdentifier)
        }

        switch profile.privacy.storage {
        case .providerDefault:
            break
        case .disabled:
            object["store"] = .bool(false)
        case .enabled:
            object["store"] = .bool(true)
        }

        return .object(object)
    }

    private static func anthropicMessagesBody(
        request: ModelRequest,
        target: ProviderTarget,
        environment: CompiledEnvironment
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(target.modelID),
            "max_tokens": .integer(request.maxOutputTokens ?? 1_024),
            "system": .string(
                combinedInstructions(request.instructions, environment.semanticInstructions)
            ),
            "messages": messageArray(request.messages),
        ]

        if request.webSearchEnabled {
            let tool: [String: JSONValue] = [
                "type": .string(target.anthropicWebSearchTool.rawValue),
                "name": .string("web_search"),
                "max_uses": .integer(5),
                "user_location": environment.nativeLocation,
            ]

            object["tools"] = .array([.object(tool)])
        }

        if let stableUserIdentifier = request.stableUserIdentifier {
            object["metadata"] = .object([
                "user_id": .string(stableUserIdentifier),
            ])
        }

        return .object(object)
    }

    private static func openRouterChatBody(
        request: ModelRequest,
        profile: EnvironmentProfile,
        target: ProviderTarget,
        environment: CompiledEnvironment
    ) -> JSONValue {
        var messages: [JSONValue] = [
            .object([
                "role": .string("system"),
                "content": .string(
                    combinedInstructions(request.instructions, environment.semanticInstructions)
                ),
            ]),
        ]
        messages.append(contentsOf: request.messages.map(messageObject))

        var object: [String: JSONValue] = [
            "model": .string(target.modelID),
            "messages": .array(messages),
        ]

        if let maxOutputTokens = request.maxOutputTokens {
            object["max_tokens"] = .integer(maxOutputTokens)
        }

        if request.webSearchEnabled {
            object["tools"] = .array([
                .object([
                    "type": .string("openrouter:web_search"),
                    "parameters": .object([
                        "engine": .string("native"),
                        "user_location": environment.nativeLocation,
                    ]),
                ]),
            ])
        }

        if let stableUserIdentifier = request.stableUserIdentifier {
            object["user"] = .string(stableUserIdentifier)
        }

        var provider: [String: JSONValue] = [:]
        if request.webSearchEnabled {
            provider["require_parameters"] = .bool(true)
        }

        switch profile.privacy.dataCollection {
        case .providerDefault:
            break
        case .deny:
            provider["data_collection"] = .string("deny")
        case .allow:
            provider["data_collection"] = .string("allow")
        }

        if profile.privacy.requireZeroDataRetention {
            provider["zdr"] = .bool(true)
        }

        if !provider.isEmpty {
            object["provider"] = .object(provider)
        }

        return .object(object)
    }

    private static func messageArray(_ messages: [ModelMessage]) -> JSONValue {
        .array(messages.map(messageObject))
    }

    private static func messageObject(_ message: ModelMessage) -> JSONValue {
        .object([
            "role": .string(message.role.rawValue),
            "content": .string(message.content),
        ])
    }

    private static func combinedInstructions(
        _ requestInstructions: String?,
        _ environmentInstructions: String
    ) -> String {
        [requestInstructions, environmentInstructions]
            .compactMap { value in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: "\n\n")
    }

    private static func appendOpenAIPrivacyReport(
        _ privacy: PrivacyPreferences,
        to entries: inout [EnvironmentReportEntry]
    ) {
        guard privacy.storage != .providerDefault else {
            return
        }
        entries.append(
            .init(
                dimension: "provider_storage",
                requestedValue: privacy.storage.rawValue,
                delivery: .native,
                status: .applied,
                detail: "Mapped to the OpenAI Responses store field."
            )
        )
    }

    private static func appendOpenRouterPrivacyReport(
        _ privacy: PrivacyPreferences,
        to entries: inout [EnvironmentReportEntry]
    ) {
        if privacy.dataCollection != .providerDefault {
            entries.append(
                .init(
                    dimension: "data_collection",
                    requestedValue: privacy.dataCollection.rawValue,
                    delivery: .native,
                    status: .applied,
                    detail: "Mapped to OpenRouter provider.data_collection."
                )
            )
        }

        if privacy.requireZeroDataRetention {
            entries.append(
                .init(
                    dimension: "zero_data_retention",
                    requestedValue: "required",
                    delivery: .native,
                    status: .applied,
                    detail: "Mapped to OpenRouter provider.zdr."
                )
            )
        }

        if privacy.storage != .providerDefault {
            entries.append(
                .init(
                    dimension: "provider_storage",
                    requestedValue: privacy.storage.rawValue,
                    delivery: .omitted,
                    status: .unsupported,
                    detail: "OpenRouter Chat does not use this profile setting as a storage guarantee."
                )
            )
        }
    }

    private static func appendUnsupportedPrivacyReport(
        _ privacy: PrivacyPreferences,
        providerName: String,
        to entries: inout [EnvironmentReportEntry]
    ) {
        if privacy.storage != .providerDefault {
            entries.append(
                .init(
                    dimension: "provider_storage",
                    requestedValue: privacy.storage.rawValue,
                    delivery: .omitted,
                    status: .unsupported,
                    detail: "\(providerName) has no matching request field in this prototype."
                )
            )
        }

        if privacy.dataCollection != .providerDefault || privacy.requireZeroDataRetention {
            entries.append(
                .init(
                    dimension: "provider_privacy_routing",
                    requestedValue: privacy.requireZeroDataRetention ? "zdr" : privacy.dataCollection.rawValue,
                    delivery: .omitted,
                    status: .unsupported,
                    detail: "\(providerName) has no matching per-request routing field in this prototype."
                )
            )
        }
    }

    private static func decodeOpenAIStreamEvent(
        _ event: SSEEvent,
        pendingCompletion: inout ModelCompletionStatus?
    ) throws -> [ModelStreamEvent] {
        if event.data == "[DONE]" {
            return [terminalEvent(pendingCompletion ?? .completed)]
        }

        let object = try decodeJSONObject(Data(event.data.utf8))
        let type = object["type"] as? String ?? event.name

        switch type {
        case "response.created":
            return [.started]
        case "response.output_text.delta":
            if let delta = object["delta"] as? String {
                return [.textDelta(delta)]
            }
            throw PackagisError.malformedResponse(
                "OpenAI text delta event did not contain delta."
            )
        case "response.refusal.delta":
            if let delta = object["delta"] as? String {
                return [.textDelta(delta)]
            }
            throw PackagisError.malformedResponse(
                "OpenAI refusal delta event did not contain delta."
            )
        case "response.refusal.done":
            pendingCompletion = .refused
            return [.providerEvent(event)]
        case "response.completed":
            return [terminalEvent(pendingCompletion ?? .completed)]
        case "response.incomplete":
            return [.incomplete(reason: openAIIncompleteReason(object))]
        case "error", "response.failed":
            throw PackagisError.providerError(providerErrorMessage(object))
        default:
            return [.providerEvent(event)]
        }
    }

    private static func decodeAnthropicStreamEvent(
        _ event: SSEEvent,
        pendingCompletion: inout ModelCompletionStatus?
    ) throws -> [ModelStreamEvent] {
        let object = try decodeJSONObject(Data(event.data.utf8))
        let type = object["type"] as? String ?? event.name

        switch type {
        case "message_start":
            return [.started]
        case "content_block_delta":
            let delta = object["delta"] as? [String: Any]
            guard delta?["type"] as? String == "text_delta" else {
                return [.providerEvent(event)]
            }
            if let text = delta?["text"] as? String {
                return [.textDelta(text)]
            }
            throw PackagisError.malformedResponse(
                "Anthropic text delta event did not contain text."
            )
        case "message_delta":
            guard
                let delta = object["delta"] as? [String: Any],
                let stopReason = delta["stop_reason"] as? String
            else {
                return [.providerEvent(event)]
            }
            let completion = completionStatus(
                stopReason: stopReason,
                completeReasons: ["end_turn", "stop_sequence"]
            )
            pendingCompletion = completion
            var events: [ModelStreamEvent] = [.providerEvent(event)]
            if completion == .refused {
                events.append(.discardedText(reason: stopReason))
            }
            return events
        case "message_stop":
            guard let completion = pendingCompletion else {
                throw PackagisError.malformedResponse(
                    "Anthropic message_stop arrived without a stop_reason."
                )
            }
            return [terminalEvent(completion)]
        case "error":
            throw PackagisError.providerError(providerErrorMessage(object))
        default:
            return [.providerEvent(event)]
        }
    }

    private static func decodeOpenRouterStreamEvent(
        _ event: SSEEvent,
        pendingCompletion: inout ModelCompletionStatus?
    ) throws -> [ModelStreamEvent] {
        if event.data == "[DONE]" {
            guard let completion = pendingCompletion else {
                throw PackagisError.malformedResponse(
                    "OpenRouter [DONE] arrived without a finish_reason."
                )
            }
            return [terminalEvent(completion)]
        }

        let object = try decodeJSONObject(Data(event.data.utf8))

        if containsError(object) {
            throw PackagisError.providerError(providerErrorMessage(object))
        }

        let choices = object["choices"] as? [[String: Any]] ?? []
        for choice in choices where openRouterChoiceContainsError(choice) {
            throw PackagisError.providerError(providerErrorMessage(choice))
        }
        let deltas = choices.compactMap { choice -> String? in
            let delta = choice["delta"] as? [String: Any]
            return delta?["content"] as? String
        }
        let finishReasons = choices.compactMap { choice -> String? in
            choice["finish_reason"] as? String
        }

        if !finishReasons.isEmpty {
            let incompleteReasons = finishReasons.filter { $0 != "stop" }
            pendingCompletion = incompleteReasons.isEmpty
                ? .completed
                : .incomplete(
                    reason: Array(Set(incompleteReasons)).sorted().joined(separator: ",")
                )
        }

        if deltas.isEmpty {
            return [.providerEvent(event)]
        }

        var events = deltas.map(ModelStreamEvent.textDelta)
        if !finishReasons.isEmpty {
            events.append(.providerEvent(event))
        }
        return events
    }

    private static func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        do {
            let value = try JSONSerialization.jsonObject(with: data)
            guard let object = value as? [String: Any] else {
                throw PackagisError.malformedResponse("Expected a JSON object.")
            }
            return object
        } catch let error as PackagisError {
            throw error
        } catch {
            throw PackagisError.malformedResponse("Invalid JSON.")
        }
    }

    private static func providerErrorMessage(_ object: [String: Any]) -> String {
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }

        if let error = object["error"] as? String {
            return error
        }

        if let response = object["response"] as? [String: Any],
           let error = response["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }

        if let message = object["message"] as? String {
            return message
        }

        return "The provider reported an unspecified error."
    }

    private static func containsError(_ object: [String: Any]) -> Bool {
        guard let error = object["error"] else {
            return object["type"] as? String == "error"
        }
        return !(error is NSNull)
    }

    private static func openRouterChoiceContainsError(_ choice: [String: Any]) -> Bool {
        containsError(choice) || choice["finish_reason"] as? String == "error"
    }

    private static func openAIIncompleteReason(_ object: [String: Any]) -> String? {
        if let details = object["incomplete_details"] as? [String: Any] {
            return details["reason"] as? String
        }

        if let response = object["response"] as? [String: Any],
           let details = response["incomplete_details"] as? [String: Any]
        {
            return details["reason"] as? String
        }

        return nil
    }

    private static func completionStatus(
        stopReason: String,
        completeReasons: Set<String>
    ) -> ModelCompletionStatus {
        if stopReason == "refusal" {
            return .refused
        }
        return completeReasons.contains(stopReason)
            ? .completed
            : .incomplete(reason: stopReason)
    }

    private static func terminalEvent(
        _ completion: ModelCompletionStatus
    ) -> ModelStreamEvent {
        switch completion {
        case .completed:
            .completed
        case let .incomplete(reason):
            .incomplete(reason: reason)
        case .refused:
            .refused
        }
    }
}

private extension ModelCompletionStatus {
    var allowsEmptyText: Bool {
        switch self {
        case .incomplete, .refused:
            return true
        case .completed:
            return false
        }
    }
}

struct ProviderStreamDecoder {
    private let provider: ProviderID
    private var pendingCompletion: ModelCompletionStatus?

    init(provider: ProviderID) {
        self.provider = provider
    }

    mutating func decode(_ event: SSEEvent) throws -> [ModelStreamEvent] {
        try ProviderAdapters.decodeStreamEvent(
            provider: provider,
            event: event,
            pendingCompletion: &pendingCompletion
        )
    }
}
