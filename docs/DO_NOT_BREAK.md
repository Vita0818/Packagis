# DO_NOT_BREAK

## 外部依赖优先与禁止功能兜底（Vitemis 强制规则）

本项目继承 `/Users/vita/Vitemis/docs/DEPENDENCY_POLICY.md`。本节是强制约束，不是建议。

- 当用户指定、仓库已经采用，或经许可证、provenance、安全与平台审查可采用的外部依赖提供同等能力时，必须直接集成该依赖的官方 API 或官方扩展点。
- 不得自行重写同等能力，不得新增替代 adapter、shim、compatibility layer、wrapper、proxy、facade、协议翻译层、parallel backend、preview backend、shadow implementation 或“先兜底、以后再换”的实现。
- 本地代码只允许保留官方 API 必需的最薄生命周期、类型、权限、配置和 bundle 接线；不得重新实现、解释、扩展或替代依赖的核心能力。
- exact 依赖因版本、构建、签名、许可证、平台、安全或官方 API 限制无法接入时，必须停止该能力、明确失败、报告 blocker 并请求用户决定；不得静默降级、切换 legacy/另一 provider/backend、使用 cache/mock/简化路径或继续交付不完整替代实现。
- 现有 fallback、adapter 或重复实现不构成先例，后续不得扩展。安全 fail-closed 与明确要求的旧数据解码/迁移不是功能兜底，但必须保持最窄范围，不能演化成备用产品实现。
- 只有用户针对 exact 依赖、exact 范围和退出条件作出的新明文决定才能例外。

本文记录 Packagis 原型不可破坏的工程、安全和协议边界。

## Git 与仓库

- Git root 必须为 `/Users/vita/Vitemis/Packagis`。
- `origin` 应为 `https://github.com/Vita0818/Packagis.git`。
- 不直接修改 `.git/`，也不把 Packagis 文件提交到 Vitemis 父仓库。
- 未经用户明文要求，不 add、commit、push、改 remote、建分支或 PR。
- 禁止破坏性 Git 操作和历史重写。

## 工程边界

- 保持 Swift tools 5.10、macOS 13+、iOS 16+ 和三个现有 SwiftPM target，
  除非任务明确要求改变兼容范围。
- `Sources/Packagis/` 是无 UI library；不得无意引入 SwiftUI/AppKit、
  会话持久化或宿主产品状态。
- 未经明确要求，不新增第三方依赖、CI、配置读取器或发布工程。
- `.build/`、`.swiftpm/` 和 DerivedData 是可再生生成物。

## 请求与身份不变量

- 原始用户消息与环境语义指令必须分离；地区层不得改写用户消息。
- `EnvironmentProfile` 不得包含 API key、组织、项目、账单、KYC、
  账号国家或代理凭据。
- 稳定的 `safety_identifier`、`user`、`metadata.user_id` 不得因档案切换
  而自动变化。
- `PreparedRequest` 和 preview 不含凭据；认证只在发送时注入。
- 认证头必须经过 provider 白名单，目标必须是对应 provider 官方 HTTPS
  origin，redirect 必须拒绝。
- 禁止生成 `Forwarded`、`X-Forwarded-For`、`CF-Connecting-IP`、
  `True-Client-IP` 等伪造来源头。

## Provider 协议不变量

- OpenAI Responses、Anthropic Messages 与 OpenRouter Chat 保持独立 adapter
  和独立 SSE 终态，不用一种 provider 的事件规则猜测另一种。
- Anthropic decoder 当前只对应 `2023-06-01`，因此请求版本必须固定一致。
- Web Search location 只放入 provider 正式定义的位置结构，不把经纬度塞入
  prompt、metadata 或未知字段。
- OpenRouter native search 的位置只能报告为 `providerDependent`，除非未来
  有可验证的模型能力/最终路由证据。
- `stream` body 字段必须与 `Accept` 头同步；JSON 编码保持确定性 sorted keys。
- provider error、choice 级错误、非 2xx 错误和 OpenAI incomplete 不得被
  当作普通完整成功响应。
- Anthropic 流式 refusal 必须在 refused 前发出 `discardedText`，让宿主
  撤回中途文本；不得把拒绝前的部分输出当作最终内容。

## SSE 不变量

- 继续支持 CRLF/LF、UTF-8 分片、BOM、注释、多行 data 和缺少最后空行。
- 保持行、事件、缓冲区和单事件行数上限。
- 短事件必须在换行处及时交付，不能固定等待 4 KiB。
- 收到首个 provider 终态后结束上层流，避免重复完成事件或等待不关闭的连接。
- 流缓冲必须保持有界；慢消费者不得导致无限内存增长或静默丢失 token。
- 提前停止消费时保留 `ModelStream.cancel()` 的显式取消路径。

## 明确不支持

- 控制第三方桌面 App、TLS MITM、浏览器指纹或伪造真实物理位置。
- 改变账号地区、账单/KYC、真实出口 IP 或 provider 服务端观测事实。
- 将语言偏好或搜索目标宣传为身份替换。
- 当前没有自定义可信 gateway、显式代理或代理失败 fallback。

## 验证要求

源码变更至少运行：

```sh
swift test --scratch-path .build
git diff --check
git status --short
```

涉及 mock 演示或公共 API 时同时运行：

```sh
swift run PackagisPrototype
```
