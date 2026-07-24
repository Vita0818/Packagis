# Packagis

Packagis is a stateless Swift Package prototype for Apple applications. It
normalizes a text request, compiles a language and region profile into the
official request surface of a provider, sends the request through an injected
transport, and normalizes single or streaming text responses.

The package intentionally contains no SwiftUI/AppKit UI, local conversation
store, API key file reader, browser fingerprint patching, or HTTPS interception.

## Prototype scope

- Swift 5.10 package with no third-party dependencies.
- macOS 13+ and iOS 16+.
- OpenAI Responses request and typed SSE normalization.
- Anthropic Messages request and SSE normalization.
- OpenRouter Chat Completions request and SSE normalization.
- Completion status distinguishes completed, incomplete, and refused outcomes
  while preserving Anthropic `stop_reason` and OpenRouter `finish_reason`.
- Language, time zone, date, currency, and unit preferences through a separate
  high-priority instruction.
- Approximate Web Search location mapped to each provider's documented field.
  Actual effect still depends on provider and model capability; OpenRouter may
  fall back to a search engine that ignores the supplied location.
- OpenRouter `provider.data_collection`, `provider.zdr`, and
  `provider.require_parameters` mapping.
- Deterministic Mock transport and request previews that contain no credentials.

The executable demo and all tests use only `MockTransport`; they do not contact
any provider. `PackagisClient()` also defaults to `MockTransport`, so enabling
live traffic requires explicitly injecting `URLSessionTransport()`.

## Run the prototype

```sh
swift run PackagisPrototype
swift test
```

The demo prints the prepared OpenAI Responses JSON, a normalized non-stream
mock response, and normalized mock stream events.

Streaming consumers should treat `discardedText(reason:)` as an instruction to
remove previously rendered partial text; Anthropic uses this path for a
mid-stream refusal before the final `.refused` event.

If a consumer intentionally stops before a terminal event, call
`ModelStream.cancel()` to cancel the underlying parser and transport task
immediately.

## Embed in another Apple application

```swift
import Foundation
import Packagis

let transport = MockTransport(replies: [
    .response(
        HTTPResponse(
            statusCode: 200,
            body: Data(#"{"output_text":"Mock answer"}"#.utf8)
        )
    )
])

let client = PackagisClient(transport: transport)

let profile = EnvironmentProfile(
    id: "us-new-york-en",
    response: ResponsePreferences(
        languageTag: "en-US",
        timeZoneIdentifier: "America/New_York",
        spelling: .american,
        currencyCode: "USD",
        unitSystem: .us
    ),
    location: ApproximateLocation(
        countryCode: "US",
        region: "New York",
        city: "New York"
    )
)

let prepared = try client.prepare(
    ModelRequest(
        messages: [.init(role: .user, content: "What is happening nearby?")],
        webSearchEnabled: true,
        stableUserIdentifier: "stable-anonymous-user"
    ),
    profile: profile,
    target: ProviderTarget(
        provider: .openAIResponses,
        modelID: "your-model-id"
    ),
    referenceDate: Date()
)

let preview = try prepared.preview(for: .single)
let response = try await client.send(prepared)
```

`PreparedRequest` never contains credentials. `URLSessionTransport` is already
available, but this prototype performs no live-provider validation and includes
no configuration or Keychain reader. A future host application owns those
boundaries and supplies only provider-approved authentication headers at send
time:

```swift
let credentials = ClosureCredentialProvider { target in
    // Load from the host application's configuration/Keychain boundary.
    // Do not hard-code or log the returned value.
    switch target.provider {
    case .openAIResponses, .openRouterChat:
        return ["Authorization": "Bearer <value supplied by host>"]
    case .anthropicMessages:
        return ["x-api-key": "<value supplied by host>"]
    }
}
```

Prepared targets are restricted to the selected provider's official HTTPS
origin. The prototype does not yet expose an opt-in trust policy for compatible
gateways or private endpoints.

`maxOutputTokens`, when supplied, must be greater than zero because this
prototype only supports text-generation requests. Anthropic is pinned to the
`2023-06-01` Messages protocol implemented by the stream decoder.

Packagis does not claim that response preferences or Web Search location change
the provider account region, network source, billing identity, or physical
location. A real request uses the host application's actual macOS/iOS network
route; on macOS that may include a separately configured system proxy or VPN.
