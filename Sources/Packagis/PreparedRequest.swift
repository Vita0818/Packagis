import Foundation

public struct RequestPreview: Equatable, Sendable {
    public var request: HTTPRequest
    public var report: PreparationReport

    public init(request: HTTPRequest, report: PreparationReport) {
        self.request = request
        self.report = report
    }
}

public struct PreparedRequest: Sendable {
    public let target: ProviderTarget
    public let report: PreparationReport

    let bodyTemplate: JSONValue
    let baseHeaders: [String: String]

    init(
        target: ProviderTarget,
        bodyTemplate: JSONValue,
        baseHeaders: [String: String],
        report: PreparationReport
    ) {
        self.target = target
        self.bodyTemplate = bodyTemplate
        self.baseHeaders = baseHeaders
        self.report = report
    }

    public func preview(for deliveryMode: DeliveryMode) throws -> RequestPreview {
        guard var object = bodyTemplate.objectValue else {
            throw PackagisError.invalidRequest("Prepared body must be a JSON object.")
        }

        object["stream"] = .bool(deliveryMode == .streaming)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(JSONValue.object(object))

        var headers = baseHeaders
        headers["Accept"] = deliveryMode == .streaming
            ? "text/event-stream"
            : "application/json"

        return RequestPreview(
            request: HTTPRequest(
                url: target.endpoint,
                headers: headers,
                body: data
            ),
            report: report
        )
    }
}
