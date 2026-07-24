# ARCHITECTURE

## 外部依赖优先与禁止功能兜底（Vitemis 强制规则）

本项目继承 `/Users/vita/Vitemis/docs/DEPENDENCY_POLICY.md`。本节是强制约束，不是建议。

- 当用户指定、仓库已经采用，或经许可证、provenance、安全与平台审查可采用的外部依赖提供同等能力时，必须直接集成该依赖的官方 API 或官方扩展点。
- 不得自行重写同等能力，不得新增替代 adapter、shim、compatibility layer、wrapper、proxy、facade、协议翻译层、parallel backend、preview backend、shadow implementation 或“先兜底、以后再换”的实现。
- 本地代码只允许保留官方 API 必需的最薄生命周期、类型、权限、配置和 bundle 接线；不得重新实现、解释、扩展或替代依赖的核心能力。
- exact 依赖因版本、构建、签名、许可证、平台、安全或官方 API 限制无法接入时，必须停止该能力、明确失败、报告 blocker 并请求用户决定；不得静默降级、切换 legacy/另一 provider/backend、使用 cache/mock/简化路径或继续交付不完整替代实现。
- 现有 fallback、adapter 或重复实现不构成先例，后续不得扩展。安全 fail-closed 与明确要求的旧数据解码/迁移不是功能兜底，但必须保持最窄范围，不能演化成备用产品实现。
- 只有用户针对 exact 依赖、exact 范围和退出条件作出的新明文决定才能例外。

最近自查日期：2026-07-23

## 当前架构

Packagis 是无 UI、无持久化的进程内 Swift library。当前主链路为：

```text
ModelRequest + EnvironmentProfile + ProviderTarget
  → EnvironmentCompiler
  → ProviderAdapters
  → PreparedRequest（无凭据）
  → CredentialProvider（发送时注入）
  → HTTPTransport
  → OpenAI / Anthropic / OpenRouter
  → 非流式或 SSE 响应归一化
```

宿主应用负责选择档案、模型和凭据来源；Packagis 不读取配置文件、
Keychain 或环境变量。

## 编译与请求准备

1. `EnvironmentProfileValidator` 校验结构化语言、时区、货币和近似地点。
2. `EnvironmentCompiler` 生成单独的地区语义指令、原生搜索位置对象和
   `PreparationReport`。
3. `ProviderAdapters` 将 canonical request 映射到具体 provider schema。
4. `PreparedRequest.preview` 按单次/流式模式确定性编码 JSON，并设置
   `stream` 与 `Accept`；预览不含凭据。
5. 目标 URL 必须位于 provider 官方 HTTPS origin。

地区层不修改原始 `ModelMessage`，也不把网络位置或身份信息混入档案。

## Provider 映射

- OpenAI Responses：`instructions`、`input`、`max_output_tokens`、
  Web Search `user_location`、`safety_identifier`、`store`。
- Anthropic Messages：固定 `anthropic-version: 2023-06-01`，使用顶层
  `system`、`messages`、`max_tokens`、Web Search `user_location` 和
  `metadata.user_id`。
- OpenRouter Chat：`system` message、`messages`、`max_tokens`、
  `openrouter:web_search`、`user`、provider 隐私/参数路由与真实 App
  attribution 头。

OpenRouter 的搜索位置报告为 `providerDependent`：adapter 已请求 native
search，但无法在本地证明最终模型/搜索引擎采用位置。

## 认证与网络

- `CredentialProvider` 只在 `send`/`stream` 前返回认证头。
- 认证头按 provider 白名单限制；来源位置头（例如
  `X-Forwarded-For`）不会被接受。
- `URLSessionTransport` 使用 ephemeral configuration，并拒绝 HTTP redirect。
- `MockTransport` 记录请求并按队列返回 fixture。
- `PackagisClient()` 默认选择 `MockTransport`；真实网络必须由宿主显式启用。
- 非 2xx 响应最多读取 64 KiB 错误体；provider message 会进入类型化错误。

没有 Shadowrocket 专用代码。真实 `URLSession` 请求会使用系统实际网络
路线；若 Shadowrocket 接管系统代理或 TUN，它位于 Packagis 与 provider
之间。当前没有代理探测、出口诊断或 silent-fallback 控制。

## 响应与流

- 非流式路径只接受预期文本结构；provider error 和缺少文本会显式失败。
- OpenAI、Anthropic、OpenRouter 各自使用独立 SSE 事件解码规则。
- OpenAI `response.completed`、`response.incomplete`，Anthropic
  `message_stop`，以及 OpenRouter `[DONE]` 是各自终态。
- Anthropic/OpenRouter 的语义 stop/finish reason 会单独判断；截断、
  refusal 或需要工具/续跑的结果不会报告为完整完成。
- Anthropic 流中途 refusal 会先产生 `discardedText(reason:)`，要求宿主撤回
  已展示的部分文本，再在 `message_stop` 时以 refused 结束。
- 首个终态会结束上层 stream，不继续等待连接 EOF。
- 传输层和归一化层使用有界缓冲；producer 在缓冲区满时协作等待消费者。
- 调用方提前停止消费但继续持有 stream 时，必须调用公开的
  `ModelStream.cancel()` 立即取消底层任务。
- SSE parser 支持任意字节切分、UTF-8、BOM、注释、多行 data、CRLF/LF，
  并限制行、事件、缓冲区和单事件行数。

## 当前安全边界

- 不读取、保存或打印真实凭据。
- 不改写第三方 App 流量，不做 TLS MITM。
- 不伪造 IP 来源头、账号国家、账单或 KYC。
- 稳定用户标识属于调用请求，不由地区档案生成或轮换。
- 搜索位置只代表检索目标，不代表真实网络或身份。

## 尚未形成的架构

macOS App/UI、本地会话、配置/Keychain、持久化、IPC、模型能力矩阵、
显式代理、出口诊断、完整背压、CI 与发布链路仍未实现。
