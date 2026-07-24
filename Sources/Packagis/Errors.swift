import Foundation

public enum PackagisError: Error, Equatable, LocalizedError, Sendable {
    case invalidProfile(String)
    case invalidRequest(String)
    case invalidCredentialHeader(String)
    case noMockReply
    case wrongMockReplyKind
    case invalidHTTPResponse
    case httpStatus(Int, message: String?)
    case invalidContentType(String?)
    case malformedResponse(String)
    case providerError(String)
    case malformedSSE(String)
    case SSELimitExceeded

    public var errorDescription: String? {
        switch self {
        case let .invalidProfile(message):
            "Invalid environment profile: \(message)"
        case let .invalidRequest(message):
            "Invalid request: \(message)"
        case let .invalidCredentialHeader(header):
            "Credential source returned a disallowed header: \(header)"
        case .noMockReply:
            "Mock transport has no queued reply."
        case .wrongMockReplyKind:
            "Mock reply does not match the requested delivery mode."
        case .invalidHTTPResponse:
            "The transport did not return a valid HTTP response."
        case let .httpStatus(statusCode, message):
            if let message {
                "The provider returned HTTP \(statusCode): \(message)"
            } else {
                "The provider returned HTTP \(statusCode)."
            }
        case let .invalidContentType(contentType):
            "Expected text/event-stream but received \(contentType ?? "no Content-Type")."
        case let .malformedResponse(message):
            "Malformed provider response: \(message)"
        case let .providerError(message):
            "Provider error: \(message)"
        case let .malformedSSE(message):
            "Malformed SSE stream: \(message)"
        case .SSELimitExceeded:
            "SSE line, event, or buffer limit exceeded."
        }
    }
}
