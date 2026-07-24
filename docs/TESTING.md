# TESTING

## 外部依赖与禁止兜底验证（Vitemis 强制规则）

本项目继承 `/Users/vita/Vitemis/docs/DEPENDENCY_POLICY.md`。涉及外部能力的变更必须验证：

- exact 外部依赖可用时只调用其官方 API/扩展点，不调用第一方重复实现。
- 依赖缺失、版本不兼容或构建/签名/许可证/平台/安全条件不成立时，产生明确、可诊断失败并停止该能力。
- 失败路径不会切换到 legacy、另一 provider/backend、adapter/shim、cache、mock、简化实现或不完整路径。
- 测试 double 只存在于测试 target，不进入 production selection 或 runtime fallback。
- Review 检查新增 wrapper/adapter/facade 是否仅为官方 API 必需的最薄接线；发现核心能力复制、第二实现或静默降级即判定失败。

最近自查日期：2026-07-23

## 环境

- 仓库：`/Users/vita/Vitemis/Packagis`
- 构建系统：Swift Package Manager
- manifest：Swift tools version 5.10
- 平台：macOS 13+、iOS 16+
- 第三方依赖：无
- 测试凭据：不需要；测试和演示不得读取真实 key 或调用真实 provider

## 命令

构建：

```sh
swift build
```

运行全部测试：

```sh
swift test --scratch-path .build
```

运行 mock 演示：

```sh
swift run PackagisPrototype
```

只运行一个 XCTest：

```sh
swift test --filter PackagisTests.ClientTests/testOpenAIStreamNormalization
```

## 当前结果

2026-07-23 实际运行：

- `swift test --scratch-path .build`
- 44 个 XCTest，0 failure。
- `swift run PackagisPrototype`
- 成功打印无凭据 OpenAI 请求预览、归一化 mock 单次响应和 mock 流事件。

SwiftPM 在受限执行环境下可能需要允许其调用系统构建沙箱；这不代表测试
访问网络。所有 fixture 都通过 `MockTransport` 注入。

## 当前覆盖

- 三家 provider 请求 JSON、header 和隐私字段映射。
- 环境指令、Web Search 近似位置、稳定用户标识和确定性准备。
- IANA 时区、结构化语言/国家/货币和控制字符校验。
- 官方 endpoint 限制与 OpenRouter attribution header 校验。
- 凭据仅发送时注入、认证头白名单和伪造来源头拒绝。
- 三家非流式文本响应、provider/HTTP/choice 错误解析。
- OpenAI complete/incomplete/refusal、Anthropic `stop_reason`/`message_stop`、
  OpenRouter `finish_reason`/`[DONE]`。
- SSE 任意字节分片、CRLF、BOM、注释、多行 data、缺少尾部空行及资源上限。
- 有界 backpressure 在慢消费者下保持事件顺序且不丢失。
- `ModelStream.cancel()` 会终止仍在等待数据的底层 source。
- OpenRouter 搜索位置报告为 `providerDependent`。

## 尚未覆盖

- 真实 OpenAI、Anthropic、OpenRouter 网络集成。
- URLSession 本地服务器时序、redirect、取消、慢消费者与长流压力测试。
- Shadowrocket、系统代理、出口 IP、DNS 或 fallback。
- Keychain、配置文件、持久化、App UI、签名、公证和发布。
- 文件、多模态、工具调用、Structured Output、引用与 usage。
- 完整 BCP 47/ISO 数据库成员资格、DST 边界组合和 provider 模型能力矩阵。
- CI、lint、format 和 UI 测试。

## Lint 与 Format

当前没有专用 lint 或 format 配置。未经任务授权，不运行会批量改写文件的
格式化命令。文本完整性使用：

```sh
git diff --check
rg -n '[[:blank:]]+$' Package.swift README.md Sources Tests docs AGENTS.md
```

## 仓库核对

```sh
pwd
git rev-parse --show-toplevel
git remote -v
git status --short
```

`pwd` 与 Git root 都必须是 `/Users/vita/Vitemis/Packagis`。
