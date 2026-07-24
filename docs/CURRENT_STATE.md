# CURRENT_STATE

最近一次自查日期：2026-07-23

## 当前真实状态

Packagis 已从空白仓库落地为一个可嵌入 Apple 应用的 Swift Package
mock 原型。远程仍为 `https://github.com/Vita0818/Packagis.git`。

已确认工程事实：

- Swift tools version 5.10，Swift Package Manager，无第三方依赖。
- 最低平台是 macOS 13 与 iOS 16。
- `Packagis` library target、`PackagisPrototype` executable target 和
  `PackagisTests` test target 已建立。
- 当前没有 SwiftUI/AppKit 界面、App bundle、本地会话层、持久化或配置文件读取器。

## 已实现能力

- `EnvironmentProfile`：回复语言、IANA 时区、拼写、日期顺序、时制、
  货币、单位、国家/地区/城市级近似位置和独立隐私偏好。
- 确定性的环境编译：生成单独的高优先级地区指令，不改写用户消息。
- 三个 provider adapter：
  - OpenAI Responses
  - Anthropic Messages（固定 `2023-06-01` 协议）
  - OpenRouter Chat Completions
- Web Search 近似位置映射。OpenRouter 的结果明确报告为
  `providerDependent`，不声称模型一定采用该位置。
- OpenAI `store`、OpenRouter `provider.data_collection`、`zdr` 和
  `require_parameters` 映射。
- `PreparedRequest` 与不含凭据的请求预览；凭据只在发送瞬间通过
  `CredentialProvider` 注入，并限制为 provider 允许的认证头。
- 目标 endpoint 只允许对应 provider 的官方 HTTPS origin；拒绝跳转。
- `URLSessionTransport` 与完全确定性的 `MockTransport`。
- `PackagisClient()` 默认使用 `MockTransport`；真实网络必须显式注入
  `URLSessionTransport()`。
- 三家非流式文本响应归一化，以及增量 SSE 解析、错误解析和终态处理。
- OpenAI incomplete/refusal、Anthropic `stop_reason` 与 OpenRouter
  `finish_reason` 会归一化为 completed、incomplete 或 refused。
- `PreparationReport` 说明每个环境维度的发送方式和状态。

## 已验证状态

- `swift test --scratch-path .build`：44 个 XCTest 全部通过。
- `swift run PackagisPrototype`：纯 mock 演示可运行。
- 测试和演示均不访问真实 provider，也不读取 API key。

## 尚未实现

- 真正的 macOS App、SwiftUI/AppKit、签名、公证和发布。
- 配置 schema、文件加载、Keychain、会话存储和迁移。
- 真实 provider 集成验证与模型能力矩阵。
- OpenAI Chat、OpenRouter Responses、结构化输出、文件、多模态、引用、
  任意工具调用和统一 usage。
- strict/minimal 编译模式、档案覆盖优先级、冲突解析和会话快照。
- 本地确定性日期、数字、货币和单位格式化。
- Shadowrocket 检测、显式代理、出口诊断或 fallback 控制。
- 自定义可信 gateway/private endpoint 策略。
- 完整生产级流生命周期验证、CI、lint、format、UI 测试和真实网络测试。

## 风险与边界

- Web Search location 是搜索相关性提示，不是账号、账单、KYC、出口 IP
  或真实物理位置。
- OpenRouter 即使请求 native search，也可能回退到忽略位置的搜索引擎。
- provider schema、Beta 工具和模型能力会变化；当前测试只证明本地
  adapter 与 fixture 的行为。
- 当前原型只归一化文本；工具/服务端 block 保留在 raw response 或
  provider event 中，但没有统一的结构化工具调用模型。
- Anthropic `pause_turn`/`tool_use` 会报告 incomplete，且保留原始响应，
  但本版字符串消息模型不能自动原样续接结构化 content blocks。
- 当前流使用有界缓冲和协作式 backpressure，但真实长流量集成前仍需
  专门验证取消、连接释放和慢消费者时序。
- Packagis 位于 Vitemis 父目录内，但自身是独立 Git root。

## 工作区状态

当前项目文件仍处于未跟踪状态；未执行 add、commit 或 push。
`.build/` 已由 `.gitignore` 忽略。

## 文档与源码冲突

本轮开始时，本文件及 `PROJECT_MAP.md`、`ARCHITECTURE.md`、`TESTING.md`
仍声称仓库没有源码、manifest 或测试，与当前 `Package.swift`、`Sources/`
和 `Tests/` 冲突。本轮已按源码和工程配置修正这些旧描述。
