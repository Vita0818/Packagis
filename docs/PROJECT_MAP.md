# PROJECT_MAP

最近自查日期：2026-07-23

## 目录结构

```text
Packagis/
├── Package.swift
├── README.md
├── .gitignore
├── AGENTS.md
├── CLAUDE.md
├── GEMINI.md
├── Sources/
│   ├── Packagis/
│   │   ├── EnvironmentCompiler.swift
│   │   ├── EnvironmentProfile.swift
│   │   ├── Errors.swift
│   │   ├── JSONValue.swift
│   │   ├── Models.swift
│   │   ├── PackagisClient.swift
│   │   ├── PreparedRequest.swift
│   │   ├── ProviderAdapters.swift
│   │   ├── SSEParser.swift
│   │   └── Transport.swift
│   └── PackagisPrototype/
│       └── main.swift
├── Tests/
│   └── PackagisTests/
│       ├── ClientTests.swift
│       ├── EnvironmentCompilerTests.swift
│       ├── ProviderAdapterTests.swift
│       ├── SSEParserTests.swift
│       └── TestSupport.swift
└── docs/
    ├── AGENTS.md
    ├── CLAUDE.md
    ├── GEMINI.md
    ├── AI_INTEGRATION_GUIDE.md
    ├── ARCHITECTURE.md
    ├── CURRENT_STATE.md
    ├── DO_NOT_BREAK.md
    ├── LANGUAGE_REGION_ENVIRONMENT.md
    ├── PROJECT_MAP.md
    └── TESTING.md
```

`.git/` 是 Git 内部目录，不纳入业务地图，也不得直接修改。

## Target

| Target | 类型 | 平台 | 入口 | 职责 |
|---|---|---|---|---|
| `Packagis` | Library | macOS 13+ / iOS 16+ | `PackagisClient` | 环境编译、provider 请求、传输和响应归一化 |
| `PackagisPrototype` | Executable | macOS 13+ | `main.swift` | 不含真实凭据和网络调用的 mock 演示 |
| `PackagisTests` | XCTest | macOS | XCTest cases | adapter、校验、mock client 与 SSE 回归测试 |

## 关键模块

- `EnvironmentProfile.swift`：公开地区、位置和隐私配置类型及结构校验。
- `EnvironmentCompiler.swift`：把档案编译为语义指令、原生位置和生效报告。
- `Models.swift`：canonical request、provider target、HTTP 和归一化响应类型。
- `ProviderAdapters.swift`：三家请求 JSON、隐私映射和响应/SSE 解码。
- `PreparedRequest.swift`：确定性 body、`stream`/`Accept` 切换和无凭据预览。
- `PackagisClient.swift`：prepare/send/stream 编排及发送时认证头注入。
- `Transport.swift`：真实 `URLSession` 传输抽象和 `MockTransport`。
- `SSEParser.swift`：支持分片、CRLF/LF、BOM、多行 data、注释与资源上限的解析器。
- `JSONValue.swift`：可排序、可编码的 JSON 值模型。
- `Errors.swift`：本地校验、HTTP、provider 和 SSE 错误。
- `docs/AI_INTEGRATION_GUIDE.md`：面向接手集成任务的 AI Agent 的
  mock-first 调用契约、provider 数据形状、状态机、安全边界和完成标准。

## 构建系统与生成物

- 构建系统：Swift Package Manager。
- 第三方依赖：无。
- 本地生成物：`.build/`、`.swiftpm/`、DerivedData；均不属于源码。
- 项目脚本、CI、lint 和 format 配置：尚未建立。
