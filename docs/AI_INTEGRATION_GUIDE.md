---
document_type: ai_agent_integration_contract
audience: coding_ai_agent
project: Packagis
language: zh-CN
status: current_prototype
last_verified: 2026-07-23
source_of_truth_priority:
  - Package.swift
  - Sources/Packagis
  - Tests/PackagisTests
  - this_document
---

# Packagis AI 集成契约

> 本文只面向负责把 Packagis 嵌入另一个 Apple/Swift 项目的 AI Agent。
> 它不是终端用户教程，也不是产品能力宣传页。

## 0. 规范词与冲突处理

本文使用以下规范词：

- `MUST`：必须执行；不满足时不得声称集成完成。
- `MUST NOT`：禁止执行。
- `SHOULD`：默认执行；仅在宿主项目存在可验证冲突时偏离。
- `MAY`：可选行为。
- `UNKNOWN`：当前源码没有证据，AI 不得自行补全或宣传。

若本文与当前源码、`Package.swift`、测试或仓库级 `AGENTS.md` 冲突，
AI `MUST` 以当前源码、manifest、测试和更严格的仓库规则为准，并报告冲突。

## 1. AI 的直接任务模型

把 Packagis 视为一个无状态 Swift library，而不是独立 Mac App、浏览器、
VPN、代理或会话系统。

标准调用链只有以下六步：

```text
ModelRequest + EnvironmentProfile + ProviderTarget
  -> PackagisClient.prepare(...)
  -> PreparedRequest.preview(...)
  -> PackagisClient.send(...) 或 PackagisClient.stream(...)
  -> provider 响应解码
  -> ModelResponse 或 ModelStreamEvent
```

AI `MUST` 遵守：

1. 第一轮集成只使用 `MockTransport`。
2. 先检查 `RequestPreview` 和 `PreparationReport`，再接入宿主业务逻辑。
3. 只有用户明确要求真实联网时，才注入 `URLSessionTransport` 和宿主凭据。
4. API key、组织、项目和账号身份 `MUST` 由宿主边界提供，不得进入
   `EnvironmentProfile`、`ModelRequest`、`PreparedRequest`、日志或测试夹具。
5. 响应状态 `MUST` 按 `completed`、`incomplete`、`refused` 分支处理，
   不得只读取 `text` 后假定请求完整成功。
6. 流式消费提前退出时 `MUST` 调用 `ModelStream.cancel()`。

## 2. 已实现边界

### 2.1 已实现

- Swift tools version 5.10。
- Swift Package Manager，无第三方依赖。
- macOS 13+、iOS 16+。
- OpenAI Responses API 请求和响应归一化。
- Anthropic Messages API 请求和响应归一化。
- OpenRouter Chat Completions API 请求和响应归一化。
- 单次 JSON 响应和 SSE 流式响应。
- 语言、时区、拼写、日期顺序、时间制、货币和单位的语义指令。
- Web Search 近似地点的 provider 字段映射。
- 部分 provider 隐私字段映射。
- 发送时凭据注入、无凭据请求预览。
- `MockTransport` 和显式启用的 `URLSessionTransport`。

### 2.2 未实现

AI `MUST NOT` 把以下项目描述成现有能力：

- SwiftUI、AppKit 或菜单栏 UI。
- 本地会话、消息历史或 profile 持久化。
- 配置文件、`.env`、Keychain 或 API key 读取器。
- 自动探测可用 model ID。
- 真实 provider 联网验证。
- 修改 macOS 全局语言、时区、定位或其他 App 的环境。
- 浏览器指纹修改、第三方桌面 App 流量改写或 HTTPS 中间人代理。
- Shadowrocket 配置、出口 IP 切换、DNS/TLS 指纹包装。
- 账号国家、账单、KYC、组织、项目或服务商风控身份修改。
- 自定义兼容网关或私有 endpoint；当前只接受对应 provider 的官方 HTTPS
  origin。

## 3. “环境包装”的准确含义

Packagis 只能控制由它自己构造的 API 请求字段。

| 维度 | 当前实现 | 发送方式 | 不代表什么 |
|---|---|---|---|
| 回复语言 | 是 | provider 高优先级语义指令 | 不代表账号或用户所在地 |
| 时区 | 是 | 语义指令和请求时刻的本地化表示 | 不修改系统时区或网络时区 |
| 拼写、日期、时间制、货币、单位 | 是 | 语义指令 | 不保证模型永远服从 |
| 国家、地区、城市 | 条件支持 | 仅在启用 Web Search 时写入近似位置字段 | 不改变出口 IP 或物理位置 |
| 数据存储/收集偏好 | 部分支持 | provider 正式字段 | 不构成跨 provider 的统一保证 |
| 稳定用户标识 | 是 | provider 正式身份/安全字段 | 不应随地区 profile 轮换 |
| API endpoint | 固定范围 | provider 官方 HTTPS origin | 不支持任意代理或兼容网关 |
| 出口 IP、DNS、TLS、VPN 路线 | 否 | 由宿主和操作系统网络栈决定 | 请求 JSON 无法伪造这些事实 |

`PreparationReport.status == .applied` 只表示 Packagis 已成功注入对应字段或
指令，不表示模型行为、服务端地理判断或账号属性已被改变。

如果宿主正在使用 Shadowrocket，Packagis 位于应用请求层：

```text
宿主 App
  -> Packagis 生成请求
  -> URLSession / macOS 网络栈
  -> Shadowrocket 或系统当前路线（若已配置）
  -> provider
```

Packagis 不插入 Shadowrocket 内部，也不位于 Shadowrocket 与 provider 之间。

## 4. 包接入规则

### 4.1 Swift Package 宿主

当 Packagis 与宿主项目位于相邻目录时，宿主 `Package.swift` 可使用：

```swift
dependencies: [
    .package(path: "../Packagis"),
],
targets: [
    .target(
        name: "HostCore",
        dependencies: [
            .product(name: "Packagis", package: "Packagis"),
        ]
    ),
]
```

路径 `MUST` 根据宿主仓库的真实目录调整。AI `MUST NOT` 为接入本包而复制
`Sources/Packagis/` 文件到宿主 target。

### 4.2 Xcode App 宿主

AI `SHOULD` 把 Packagis 作为 Local Package Dependency 加入工程，并只给需要
调用的 target 链接 `Packagis` library product。不要链接
`PackagisPrototype` executable。

宿主代码入口：

```swift
import Foundation
import Packagis
```

## 5. Mock-first 最小完整实现

以下代码是 AI 的默认集成基线。它不联网、不读取凭据，并可放进异步测试或
原型入口：

```swift
import Foundation
import Packagis

func runPackagisMock() async throws -> ModelResponse {
    let transport = MockTransport(replies: [
        .response(
            HTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"output_text":"Mock answer"}"#.utf8)
            )
        ),
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
        privacy: PrivacyPreferences(
            storage: .disabled,
            dataCollection: .providerDefault,
            requireZeroDataRetention: false
        )
    )

    let request = ModelRequest(
        instructions: "Answer concisely.",
        messages: [
            ModelMessage(
                role: .user,
                content: "What is happening nearby?"
            ),
        ],
        maxOutputTokens: 256,
        webSearchEnabled: true,
        stableUserIdentifier: "stable-anonymous-user"
    )

    let target = ProviderTarget(
        provider: .openAIResponses,
        modelID: "mock-openai"
    )

    let prepared = try client.prepare(
        request,
        profile: profile,
        target: target,
        referenceDate: Date(timeIntervalSince1970: 1_753_264_800)
    )

    let preview = try prepared.preview(for: .single)
    precondition(preview.request.headers["Authorization"] == nil)
    precondition(preview.report.profileID == profile.id)

    let response = try await client.send(prepared)

    switch response.completion {
    case .completed:
        return response
    case let .incomplete(reason):
        throw IntegrationError.incomplete(reason)
    case .refused:
        throw IntegrationError.refused
    }
}

enum IntegrationError: Error {
    case incomplete(String?)
    case refused
}
```

固定 `referenceDate` 只适用于测试。实际宿主请求 `SHOULD` 在准备当轮请求时
传入 `Date()`，因为该值会被转换成 profile 时区下的“当前本地时间”语义指令。

## 6. 公共输入模型

### 6.1 `EnvironmentProfile`

```swift
EnvironmentProfile(
    id: String,
    response: ResponsePreferences,
    location: ApproximateLocation? = nil,
    privacy: PrivacyPreferences = .init()
)
```

约束：

- `id`：1...128 个安全字符。
- `languageTag`：当前校验的是受限语言 tag 子集，不是完整 BCP 47
  实现。总长最多 64 个字符；首段必须是 2...3 个字母；后续每段必须是
  2...8 个字母或数字且不得为空。例如 `en-US`、`en-GB` 可用，但某些合法
  BCP 47 extension/private-use tag 仍可能被当前原型拒绝。
- `timeZoneIdentifier`：Foundation 能识别的 IANA 时区，例如
  `America/New_York`。
- `currencyCode`：如果存在，必须是三个字母，例如 `USD`。
- `countryCode`：如果存在，必须是两个字母，例如 `US`。
- `ApproximateLocation` 至少包含 `countryCode`、`region`、`city` 之一。
- 当前没有经纬度字段；AI `MUST NOT` 自行加入或伪造精确坐标。

可选枚举：

```text
SpellingPreference: american | british
DateOrder: monthDayYear | dayMonthYear | yearMonthDay
TimeCycle: twelveHour | twentyFourHour
UnitSystem: metric | us | uk
StoragePreference: providerDefault | disabled | enabled
DataCollectionPreference: providerDefault | deny | allow
```

### 6.2 `ModelRequest`

```swift
ModelRequest(
    instructions: String? = nil,
    messages: [ModelMessage],
    maxOutputTokens: Int? = nil,
    webSearchEnabled: Bool = false,
    stableUserIdentifier: String? = nil
)
```

约束：

- 至少一个 message。
- message role 只支持 `.user` 和 `.assistant`。
- message content 只支持字符串。
- `maxOutputTokens` 如果存在，必须大于零。
- `stableUserIdentifier` 如果存在，必须是 1...64 个非控制字符。
- `stableUserIdentifier` `SHOULD` 是稳定、匿名、与地区 profile 无关的标识。
- AI `MUST NOT` 为了制造不同地区身份而轮换该标识。

### 6.3 `ProviderTarget`

```swift
ProviderTarget(
    provider: ProviderID,
    modelID: String,
    endpoint: URL? = nil,
    anthropicWebSearchTool: AnthropicWebSearchTool = .basic,
    openRouterAttribution: OpenRouterAttribution? = nil
)
```

Provider 和默认 endpoint：

| ProviderID | API surface | 默认 endpoint |
|---|---|---|
| `.openAIResponses` | OpenAI Responses | `https://api.openai.com/v1/responses` |
| `.anthropicMessages` | Anthropic Messages | `https://api.anthropic.com/v1/messages` |
| `.openRouterChat` | OpenRouter Chat Completions | `https://openrouter.ai/api/v1/chat/completions` |

`modelID` 在本地只校验 1...256 个非控制字符。它是否真实存在属于 provider
运行时事实；mock 成功不代表 model ID 在线可用。

Anthropic 当前固定 `anthropic-version: 2023-06-01`。Web Search tool 可选值：

```text
basic              -> web_search_20250305
dynamicFiltering   -> web_search_20260209
responseInclusion  -> web_search_20260318
```

AI `MUST NOT` 在没有对应 model/provider 能力证据时自动切换新 tool type。

## 7. Provider 字段映射

### 7.1 OpenAI Responses

| Canonical 输入 | 发出的字段 |
|---|---|
| `modelID` | `model` |
| messages | `input` |
| 用户 instructions + 地区语义 | `instructions` |
| `maxOutputTokens` | `max_output_tokens` |
| Web Search + location | `tools[].type = web_search`、`tools[].user_location` |
| `stableUserIdentifier` | `safety_identifier` |
| storage disabled/enabled | `store = false/true` |

OpenAI 当前不映射 `dataCollection` 或
`requireZeroDataRetention`，也不会为这两个值生成专门的 report entry。
report 中没有某个 dimension 不等于支持；AI 不得根据字段名称或“没有报错”
猜测它已生效。

### 7.2 Anthropic Messages

| Canonical 输入 | 发出的字段/头 |
|---|---|
| `modelID` | `model` |
| messages | `messages` |
| 用户 instructions + 地区语义 | `system` |
| `maxOutputTokens` | `max_tokens`，缺省为 1024 |
| Web Search + location | `tools[].type/name/max_uses/user_location` |
| `stableUserIdentifier` | `metadata.user_id` |
| protocol version | `anthropic-version: 2023-06-01` |

当前 Anthropic adapter 不把 profile 隐私偏好映射到 per-request 字段。
只有请求了非默认 storage、data collection 或 ZDR 偏好时，才生成
`unsupported` report entry；全部使用默认值时没有对应 entry。

### 7.3 OpenRouter Chat

| Canonical 输入 | 发出的字段/头 |
|---|---|
| `modelID` | `model` |
| 用户 instructions + 地区语义 | 首个 `system` message |
| messages | 后续 `messages[]` |
| `maxOutputTokens` | `max_tokens` |
| Web Search + location | `openrouter:web_search` tool 的 `parameters.user_location` |
| 要求搜索参数被支持 | `provider.require_parameters = true` |
| `stableUserIdentifier` | `user` |
| data collection | `provider.data_collection` |
| zero data retention | `provider.zdr = true` |
| 可选 attribution | `HTTP-Referer`、`X-OpenRouter-Title` |

OpenRouter Web Search location 的 report 状态是 `providerDependent`。这表示
字段已写入，但最终路由可能使用忽略位置的搜索实现；AI `MUST NOT` 把它报告成
确定生效。

## 8. 预览与报告

`prepare` 本身不发送网络请求：

```swift
let prepared = try client.prepare(
    request,
    profile: profile,
    target: target,
    referenceDate: Date()
)
```

按交付模式生成预览：

```swift
let single = try prepared.preview(for: .single)
let streaming = try prepared.preview(for: .streaming)
```

差异：

| 模式 | JSON `stream` | `Accept` |
|---|---:|---|
| `.single` | `false` | `application/json` |
| `.streaming` | `true` | `text/event-stream` |

预览 body 使用 sorted-key JSON。`PreparedRequest` 和 `RequestPreview`
不含凭据；凭据只在 `send`/`stream` 的最后阶段临时注入传输请求。

AI `SHOULD` 将 report 用作可测试诊断数据：

```swift
for entry in preview.report.entries {
    switch entry.status {
    case .applied:
        break
    case .providerDependent:
        // 向宿主暴露“不保证最终生效”的诊断。
        break
    case .unsupported:
        // 不得声称该设置已发送。
        break
    case .notRequested:
        break
    }
}
```

报告字段：

```text
PreparationReport
├── profileID
├── provider
└── entries[]
    ├── dimension
    ├── requestedValue
    ├── delivery: semantic | native | transport | omitted
    ├── status: applied | providerDependent | unsupported | notRequested
    └── detail
```

当前 report 只为回复语言、时区、搜索位置和实际处理过的隐私项生成 entry。
拼写、日期顺序、时间制、货币和单位虽然会进入同一地区语义指令，但当前没有
各自独立的 report entry。AI `MUST NOT` 虚构缺失的 entry。

## 9. Mock 响应契约

`MockTransport` 按 FIFO 消耗 reply。`send` 必须匹配 `.response`，`stream`
必须匹配 `.stream`；类型不匹配会抛出 `.wrongMockReplyKind`。

三家最小非流式成功夹具：

OpenAI Responses：

```json
{"output_text":"Mock answer"}
```

Anthropic Messages：

```json
{"content":[{"type":"text","text":"Mock answer"}],"stop_reason":"end_turn"}
```

OpenRouter Chat：

```json
{"choices":[{"message":{"content":"Mock answer"},"finish_reason":"stop"}]}
```

AI `MUST` 保留 Anthropic 顶层 `stop_reason` 和 OpenRouter 每个 choice 的
`finish_reason`。缺少这些字段不是一个有效的成功夹具。

常用非完整夹具：

OpenAI：

```json
{
  "status":"incomplete",
  "output_text":"Partial",
  "incomplete_details":{"reason":"max_output_tokens"}
}
```

Anthropic：

```json
{
  "content":[{"type":"text","text":"Partial"}],
  "stop_reason":"max_tokens"
}
```

OpenRouter：

```json
{
  "choices":[
    {"message":{"content":"Partial"},"finish_reason":"length"}
  ]
}
```

拒绝和 provider error 夹具：

OpenAI 拒绝：

```json
{
  "output":[
    {
      "content":[
        {"type":"refusal","refusal":"Cannot help."}
      ]
    }
  ]
}
```

Anthropic 拒绝：

```json
{
  "content":[{"type":"text","text":"Partial text to discard"}],
  "stop_reason":"refusal"
}
```

OpenRouter provider error：

```json
{
  "choices":[
    {
      "message":{"content":"Partial"},
      "finish_reason":"error",
      "error":{"message":"upstream failed"}
    }
  ]
}
```

当前 OpenRouter decoder 把非 `stop` 的普通 finish reason 归一化为
`.incomplete(reason:)`，把 `error` 作为 `.providerError` 抛出；它没有
OpenRouter 专属的 `.refused` 映射。宿主仍必须对公共枚举的 `.refused`
保持穷尽处理。

最小 OpenAI stream mock：

```swift
let fixture = """
event: response.created
data: {"type":"response.created"}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"Hello"}

event: response.completed
data: {"type":"response.completed"}

"""

let transport = MockTransport(replies: [
    .stream(chunks: [Data(fixture.utf8)]),
])
let client = PackagisClient(transport: transport)
```

stream mock `MUST` 使用 `.stream` reply；每个 SSE event 之间必须有空行。

## 10. 非流式结果状态机

```swift
let response = try await client.send(prepared)

switch response.completion {
case .completed:
    consumeCompletedText(response.text)

case let .incomplete(reason):
    preservePartialText(response.text, reason: reason)

case .refused:
    discardOrIsolateRefusalText(response.text)
}
```

上例中的三个函数属于宿主伪代码。AI 必须把它们替换为宿主已有业务逻辑，
不得在 Packagis library 内创建 UI 或会话持久化。

状态语义：

- `.completed`：provider 终止原因被归一化为完整完成。
- `.incomplete(reason:)`：文本可能有用但不完整，宿主不得当作完整答案。
- `.refused`：provider 明确拒绝；宿主不得把此前部分文本当作完成答案。

HTTP 非 2xx、provider error object、缺失必要终止字段或 malformed JSON
会抛错，不会伪装成 `.completed`。

## 11. 流式消费契约

```swift
let stream = try await client.stream(prepared)
var accumulatedText = ""
var terminal: ModelCompletionStatus?

do {
    for try await event in stream {
        switch event {
        case .started:
            break

        case let .textDelta(delta):
            accumulatedText += delta

        case let .discardedText(reason):
            accumulatedText = ""
            recordDiscardReason(reason)

        case .completed:
            terminal = .completed

        case let .incomplete(reason):
            terminal = .incomplete(reason: reason)

        case .refused:
            accumulatedText = ""
            terminal = .refused

        case let .providerEvent(event):
            preserveProviderMetadata(event)
        }
    }
} catch is CancellationError {
    // 宿主主动取消或 task 被取消。
} catch {
    handleStreamFailure(error)
}
```

上例中的记录/处理函数属于宿主伪代码。

流式规则：

- `.discardedText(reason:)` 是删除已经渲染文本的命令，不是新的模型文本。
- Anthropic 可先发出文字，再以 `refusal` 结束；此时 Packagis 会先发
  `.discardedText(reason: "refusal")`，最终发 `.refused`。
- `.providerEvent` 用于保留未归一化的 provider 元数据，不应直接追加到文本。
- 正常流必须出现 terminal event；缺失 provider 完成标记会抛
  `.malformedResponse`。
- 如果宿主在 terminal event 前停止迭代，必须立即调用：

```swift
stream.cancel()
```

- 如果宿主把消费放进独立 `Task`，取消该 task 后仍 `SHOULD` 调用
  `stream.cancel()`，以明确释放底层解析和传输任务。

三家最小 streaming 终止协议：

| Provider | 文字事件 | 终止依据 |
|---|---|---|
| OpenAI | `response.output_text.delta` | `response.completed`、`response.incomplete` 或 `[DONE]` |
| Anthropic | `content_block_delta` | `message_delta.stop_reason` 后的 `message_stop` |
| OpenRouter | `choices[].delta.content` | 先取得 `finish_reason`，再收到 `[DONE]` |

## 12. 凭据和真实网络边界

### 12.1 默认行为

```swift
let client = PackagisClient()
```

以上代码使用空的 `MockTransport` 和 `NoCredentialProvider`。调用 `send`
会得到 `.noMockReply`，不会偷偷联网。

### 12.2 真实网络必须显式启用

只有用户明确要求联网集成时，AI 才可以组装：

```swift
let client = PackagisClient(
    transport: URLSessionTransport(),
    credentials: hostCredentialProvider
)
```

`hostCredentialProvider` 必须由宿主实现。Packagis 不负责决定凭据来源。
宿主可以在自己的安全边界中使用 Keychain、受保护配置或运行时注入，但 AI
不得读取、打印、记录、测试或复制真实秘密。

允许由 `CredentialProvider` 返回的 header：

| Provider | allowlist |
|---|---|
| OpenAI | `Authorization`、`OpenAI-Organization`、`OpenAI-Project` |
| Anthropic | `x-api-key`、`Authorization`、`anthropic-beta` |
| OpenRouter | `Authorization` |

其他 header 会抛 `.invalidCredentialHeader`。AI `MUST NOT` 添加以下伪造
来源字段：

```text
X-Forwarded-For
Forwarded
CF-Connecting-IP
True-Client-IP
X-Real-IP
```

`URLSessionTransport` 默认使用 ephemeral configuration，并拒绝 HTTP
redirect。它仍使用宿主设备的实际系统网络路线；Packagis 不改变
Shadowrocket、VPN、代理、DNS 或出口国家。

## 13. 错误处理最低要求

AI `MUST` 至少区分以下错误族：

| 错误 | 含义 | 宿主行为 |
|---|---|---|
| `.invalidProfile` | profile 格式或值无效 | 修复输入，不发送 |
| `.invalidRequest` | endpoint/model/request 无效 | 修复输入，不发送 |
| `.invalidCredentialHeader` | 凭据层返回越权 header | 阻止发送并审计宿主实现 |
| `.noMockReply` | mock 队列为空 | 补充测试夹具 |
| `.wrongMockReplyKind` | send/stream 与 mock 类型不匹配 | 修正测试 |
| `.invalidHTTPResponse` | URLSession transport 未得到有效 HTTP 响应 | 按传输失败处理，不生成模型结果 |
| `.httpStatus` | provider 返回非 2xx | 显示有限错误，不泄露凭据 |
| `.invalidContentType` | 流式响应不是 SSE | 拒绝按 stream 解析 |
| `.malformedResponse` | provider JSON/终止字段不完整 | 不生成伪完成结果 |
| `.providerError` | provider body/SSE 明确报错 | 传播为失败 |
| `.malformedSSE` / `.SSELimitExceeded` | 流非法或超过资源上限 | 终止并丢弃不可信流 |

该表列出了全部公开 `PackagisError` case，但 `send`/`stream` 还可能原样抛出
transport、credential provider 或 Swift concurrency 的其他 `Error`，例如
`URLError`、宿主凭据解析错误和 `CancellationError`。宿主不应把所有错误
强制转换成 `PackagisError`，也不应编写假定错误全集封闭的 switch。

不要用无差别 `catch { return "" }` 吞掉错误，也不要把错误文本拼接为模型回答。

## 14. AI 集成算法

接到“把 Packagis 接进另一个项目”的任务时，按以下顺序执行：

1. 阅读宿主仓库规则和 Packagis 当前源码。
2. 确认宿主最低平台满足 macOS 13+ 或 iOS 16+。
3. 把 Packagis 添加为 local Swift package dependency。
4. 只在宿主 core/network 层 `import Packagis`。
5. 根据宿主已有配置构造 `EnvironmentProfile`；不存在的值标为
   `UNKNOWN`，不得静默猜测。
6. 构造一个 provider 的 `ProviderTarget`，使用 mock model ID。
7. 使用 OpenAI/Anthropic 时，构造 success、incomplete、refused 和 error
   夹具；使用 OpenRouter 时，构造 success、incomplete 和 provider error
   夹具。无论选择哪一家，宿主都必须穷尽处理公共 `.refused` case。
8. 调用 `prepare` 并断言 preview 中无认证头。
9. 检查 `PreparationReport`，特别处理 `providerDependent` 和
   `unsupported`。
10. 实现 non-stream 状态分支。
11. 如果宿主需要流式输出，再实现完整 stream event switch 和取消路径。
12. 运行宿主测试和 Packagis 自身 `swift test`。
13. 只有用户明确要求后，才设计宿主凭据提供器和真实网络开关。

## 15. 完成判定

AI 只有在以下条件全部满足后，才可以报告 mock 集成完成：

- [ ] 宿主 target 能导入 `Packagis`。
- [ ] 没有新增第三方依赖。
- [ ] 没有把 Packagis 改造成 UI 或持久化层。
- [ ] 至少一个 provider 的 mock single request 通过。
- [ ] `.completed`、`.incomplete`、`.refused` 都有明确宿主行为。
- [ ] 请求 preview 不含凭据。
- [ ] profile report 被检查或传递给宿主诊断层。
- [ ] 如果使用 streaming，处理了全部 `ModelStreamEvent` case。
- [ ] 如果使用 streaming，提前退出路径调用 `stream.cancel()`。
- [ ] 没有真实网络请求、真实 key 或账号数据进入测试。
- [ ] 没有声称改变出口 IP、账号国家或物理位置。
- [ ] 与改动相称的 build/test 已通过。

建议验证命令：

```sh
swift build
swift test
git diff --check
git status --short
```

## 16. 源码定位

AI 在修改行为前 `MUST` 直接核对以下文件：

| 文件 | 事实来源 |
|---|---|
| `Package.swift` | 平台、products、targets、依赖 |
| `Sources/Packagis/EnvironmentProfile.swift` | profile 类型和校验 |
| `Sources/Packagis/EnvironmentCompiler.swift` | 地区语义、位置对象、report |
| `Sources/Packagis/Models.swift` | canonical model、响应和 stream event |
| `Sources/Packagis/ProviderAdapters.swift` | 三家字段映射和解码 |
| `Sources/Packagis/PreparedRequest.swift` | preview、stream 切换、sorted JSON |
| `Sources/Packagis/PackagisClient.swift` | prepare/send/stream、凭据 allowlist |
| `Sources/Packagis/Transport.swift` | URLSession 和 MockTransport |
| `Sources/Packagis/SSEParser.swift` | SSE 分片与资源限制 |
| `Tests/PackagisTests/` | 可执行协议夹具和回归要求 |

## 17. 禁止推断清单

没有新的源码、测试或 provider 官方证据时，AI `MUST NOT` 推断：

- 某个 model ID 当前存在或支持 Web Search。
- 语义指令必然改变模型的地域判断。
- Web Search location 等于用户实际所在地。
- OpenRouter 最终路由必然遵守 location。
- `provider.zdr = true` 在任意账号和下游 provider 上都可用。
- profile 隐私字段构成法律、合规或数据驻留保证。
- mock 成功等于真实 provider 已验证。
- 系统代理或 Shadowrocket 当前已启用、出口在哪个国家。
- API 字段能覆盖服务商从 IP、账号、支付、历史行为或基础设施获得的事实。

如果后续任务需要这些结论，AI 必须先取得相应运行时或官方证据，并把结果标记
为“已验证事实”“provider-dependent”或 `UNKNOWN`，不能用猜测填充。
