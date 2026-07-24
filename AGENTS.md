# Packagis 项目常驻上下文

## 外部依赖优先与禁止功能兜底（Vitemis 强制规则）

本项目继承 `/Users/vita/Vitemis/docs/DEPENDENCY_POLICY.md`。本节是强制约束，不是建议。

- 当用户指定、仓库已经采用，或经许可证、provenance、安全与平台审查可采用的外部依赖提供同等能力时，必须直接集成该依赖的官方 API 或官方扩展点。
- 不得自行重写同等能力，不得新增替代 adapter、shim、compatibility layer、wrapper、proxy、facade、协议翻译层、parallel backend、preview backend、shadow implementation 或“先兜底、以后再换”的实现。
- 本地代码只允许保留官方 API 必需的最薄生命周期、类型、权限、配置和 bundle 接线；不得重新实现、解释、扩展或替代依赖的核心能力。
- exact 依赖因版本、构建、签名、许可证、平台、安全或官方 API 限制无法接入时，必须停止该能力、明确失败、报告 blocker 并请求用户决定；不得静默降级、切换 legacy/另一 provider/backend、使用 cache/mock/简化路径或继续交付不完整替代实现。
- 现有 fallback、adapter 或重复实现不构成先例，后续不得扩展。安全 fail-closed 与明确要求的旧数据解码/迁移不是功能兜底，但必须保持最窄范围，不能演化成备用产品实现。
- 只有用户针对 exact 依赖、exact 范围和退出条件作出的新明文决定才能例外。

本文件继承 `/Users/vita/Vitemis/AGENTS.md` 中的 Vitemis 通用 Agent 规则。若本文件与通用规则冲突，在不违反系统和用户指令的前提下，以更具体、更严格的项目规则为准。

本文是 AI Agent 每轮进入 Packagis 仓库时的入口文件。执行任何代码、配置、构建脚本、测试或项目文档修改之前，必须先按顺序阅读并核对：

0. `/Users/vita/Vitemis/AGENTS.md`
1. `docs/CURRENT_STATE.md`
2. `docs/PROJECT_MAP.md`
3. `docs/ARCHITECTURE.md`
4. `docs/DO_NOT_BREAK.md`
5. `docs/TESTING.md`
6. `docs/NEXT_TARGET.md`（如果存在）

如果文档与当前源码、工程配置、测试或脚本冲突，必须以当前源码和配置为准，并在最终报告中指出冲突位置和采用源码为准的原因。

## 工作目录检查

每轮开始先在项目根目录执行：

```sh
pwd
git rev-parse --show-toplevel
git status --short
```

要求：

- `pwd` 与 Git root 都必须是 `/Users/vita/Vitemis/Packagis`。
- Packagis 是位于 Vitemis 父仓库内的独立嵌套 Git 仓库；不得把 Packagis 文件误作为父仓库改动处理。
- 如果当前目录不是 Packagis Git root，停止修改并报告路径问题。
- 先区分用户已有改动与本轮计划改动；不得覆盖、回退、格式化或清理用户已有改动。

## 修改边界

Packagis 当前是一个无 UI、无本地会话持久化的 Swift Package 原型：

- Swift tools version 5.10，Swift Package Manager，无第三方依赖。
- 支持 macOS 13+ 与 iOS 16+。
- `Sources/Packagis/` 是可嵌入 library；`Sources/PackagisPrototype/` 是纯 mock 演示入口。
- `Tests/PackagisTests/` 是 XCTest 单元测试。
- `Package.swift`、`README.md`、上述源码与测试目录是当前已确认的工程边界。

修改时：

- 先确认真实 target、公共 API 和 provider 协议，再修改对应源码与测试。
- 未经用户明确要求，不新增第三方依赖、App UI、持久化、配置/密钥读取、CI 或发布工程。
- 永远不得直接修改 `.git/` 内部文件。
- `.build/`、`.swiftpm/` 和 DerivedData 是生成物，不得作为业务源码编辑或提交。

## 禁止事项

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean`、`git checkout -- <path>`、`git restore --source`、rebase、强制 push 或历史重写。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR、不修改 remote；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交 `/Users/vita/Vitemis/Packagis` 当前 Git root 中与任务相关的文件；不得修改或提交 Vitemis 父仓库及其他项目。
- 不引入依赖，不创建或修改构建脚本、测试源码和生成工程文件，除非任务明确要求。
- 不读取、打印、摘要、复制或写入 `.env`、API key、token、密码、cookie、session、私钥、证书、provisioning profile、SSH key、Keychain 内容或账号凭据。
- 不把尚未从源码或配置确认的项目事实写成已实现能力；未知内容统一标注 `UNKNOWN` 或“需要后续确认”。

## 下一目标

`docs/NEXT_TARGET.md` 只用于记录一个已经明确的临时下一目标。没有 active target 时不保留空文件；目标完成或不再有效后删除该文件。

## 项目理解要求

修改前至少确认：

- remote 是否仍指向 `https://github.com/Vita0818/Packagis.git`。
- 当前是否已经出现源码、manifest、工程文件、入口、测试或脚本。
- 技术栈、目标平台、模块边界、数据格式、外部接口和安全机制是否已有可验证证据。
- 当前实现是否仍与 `Package.swift`、`README.md` 和 `docs/` 中记录的原型边界一致。

## 文档索引

- `docs/PROJECT_MAP.md`：目录、模块、入口、关键文件、生成物和脚本地图。
- `docs/ARCHITECTURE.md`：总体架构、主要链路、数据模型、通信和安全机制。
- `docs/CURRENT_STATE.md`：当前真实状态、已有能力、未完成项、风险和文档冲突。
- `docs/TESTING.md`：环境、构建、测试、lint/format 和手动验证方式。
- `docs/DO_NOT_BREAK.md`：Git 边界、工程禁区、数据格式、协议、路径和回归要求。
- `docs/AI_INTEGRATION_GUIDE.md`：面向 AI Agent 的嵌入与调用契约；涉及宿主集成、
  mock/provider 数据、凭据注入或请求状态机时必须额外阅读。
- `docs/NEXT_TARGET.md`：按需存在的临时目标记录，不是常驻空模板。

## 完成标准

完成任务前至少做到：

- 说明实际阅读或检查过哪些源码、配置、测试和文档。
- 只修改 Packagis 内、且属于用户当前任务范围的文件。
- 保留用户已有改动。
- 运行与任务相称的检查；纯文档任务至少运行 `git diff --check` 与 `git status --short`。
- 将已经完成的持久性改动及时回写到相关项目文档；若无需更新文档，最终报告说明原因。
- 如未运行构建或测试，最终报告明确说明。

## 最终报告格式

最终报告建议包含：

1. `MODEL_CHECK_RESULT`：当前模型名称；无法确认时写 `unknown`。
2. `PATH_CHECK_RESULT`：`pwd`、Git root 及是否匹配预期。
3. `FILES_WRITTEN`：新增或修改文件。
4. `PROJECT_AUDIT_SUMMARY`：识别到的项目结构、模块和关键链路。
5. `DOCS_CONTENT_SUMMARY`：文档内容摘要。
6. `VALIDATION_RESULT`：实际运行的命令和结果。
7. `UNCERTAINTIES`：无法确认或需要人工确认的内容。
8. `NEXT_RECOMMENDED_ACTION`：建议的下一步；不要自动扩展任务范围。
