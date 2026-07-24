# Packagis 语言与地区环境设计

状态：`Design v0.1；Swift mock 子集已实现`

最近核对日期：2026-07-23

## 1. 目标

Packagis 第一阶段把“语言与地区环境”实现为一个可验证的请求编排层：

- 让 Packagis 自己发出的模型请求稳定使用指定语言、拼写、日期、时间、货币和单位习惯。
- 在提供商正式支持时，把近似地点映射到 Web Search 的地区字段。
- 在提供商正式支持时，选择数据处理区域、下游 provider 和隐私策略。
- 让请求使用用户已经配置的真实网络路线，例如 macOS 系统网络和 Shadowrocket。
- 在发送前展示哪些设置会原生生效、哪些只是模型语义、哪些只在本地生效、哪些不受支持。

这里的“最大化”指最大化**可控性、一致性和可解释性**，不代表改变账号、账单、KYC、服务端观测事实或真实网络来源。

## 当前原型落地状态

当前源码实现的是本文设计的一个无 UI、无会话持久化子集：

- 已实现：`EnvironmentProfile`、结构校验、语义地区指令、OpenAI Responses、
  Anthropic Messages、OpenRouter Chat、三家 Web Search 近似位置映射、
  有限隐私映射、无凭据预览、发送时认证头注入、mock/URLSession transport、
  文本响应与 SSE 归一化、`PreparationReport`。
- 当前 profile 比第 4 节目标 JSON 更窄：没有 schema/version、fallback
  languages、calendar、numbering system、temperature、week start、network
  route 或 location precision。
- 当前 report 没有 `source`，状态为 `applied`、`providerDependent`、
  `unsupported`、`notRequested`。
- 当前没有完整 Profile Resolver、请求/会话优先级、冲突解析、
  `bestEffort/strict/minimal` 模式或模型能力矩阵。
- 未实现 OpenAI Chat、OpenRouter Responses、Datetime Tool、Anthropic
  `inference_geo`、provider order/allow-fallbacks、结构化本地格式化、
  Shadowrocket 诊断和出口验证。
- OpenRouter 能写入 native search location，但无法本地保证最终路由采用它；
  因此报告为 `providerDependent`，不是 `applied`。

本文其余未标为“当前实现”的内容仍是目标设计，不应被宣传为现有能力。

## 2. 必须分开的五种环境

| 环境 | 示例 | Packagis 能否控制 |
|---|---|---|
| 表达环境 | `en-US`、美式拼写、12 小时制、USD | 可以，通过模型高优先级指令和本地格式化 |
| 搜索环境 | 纽约市、美国、`America/New_York` | 部分可以，仅映射到正式的 Web Search 近似位置字段 |
| 执行环境 | OpenRouter provider、Anthropic 推理区域、ZDR | 部分可以，取决于提供商、模型和账户能力 |
| 网络环境 | 出口 IP、代理链路、DNS、TLS | 请求 JSON 不能控制；由实际网络路线决定 |
| 身份环境 | API Key、组织、项目、账单国家、安全标识 | 不属于地区档案，不允许随档案切换 |

以下概念也不能混为一谈：

- 回复语言不等于用户所在地。
- 搜索目标地点不等于用户所在地。
- Web Search 的位置提示不等于出口 IP。
- 出口 IP 不等于账号或法定身份。
- 数据处理区域不等于用户位置。

## 3. 第一版控制范围

### 3.1 本轮目标

第一版只负责 Packagis 自己构造并发送的 API 请求，或者由调用方明确交给 Packagis SDK/本地服务发送的请求。

第一版不做：

- 修改 macOS 全局语言、时区或定位。
- 修改任意第三方桌面 App 的内部状态。
- 对 HTTPS 流量进行中间人解密和任意改写。
- 伪造 `Forwarded`、`X-Forwarded-For`、`CF-Connecting-IP` 等来源头。
- 修改 API Key、组织、项目、账单、KYC 或账号国家。
- 为规避服务商限制而轮换 `user`、`safety_identifier` 或其他身份字段。
- 生成或声称一个虚构的精确住宅坐标。

如果未来需要支持自有 CLI，Packagis 可以在启动该子进程时设置 `LANG`、`LC_*` 和 `TZ`，但这些变量只影响明确由 Packagis 启动且愿意读取它们的进程，不影响其他 App。

## 4. 统一环境档案

地区能力不应被压缩成一个含糊的“国家”开关。建议内部使用以下规范化模型：

```json
{
  "schema_version": 1,
  "id": "us-new-york-en",
  "version": 1,
  "response": {
    "language_tag": "en-US",
    "fallback_language_tags": ["en"],
    "spelling": "american",
    "timezone": "America/New_York",
    "calendar": "gregory",
    "numbering_system": "latn",
    "date_order": "mdy",
    "time_cycle": "h12",
    "currency": "USD",
    "unit_system": "us",
    "temperature_unit": "fahrenheit",
    "week_start": "sunday"
  },
  "location": {
    "precision": "city",
    "country": "US",
    "region": "New York",
    "city": "New York"
  },
  "network": {
    "route": "system",
    "expected_exit_country": "US",
    "mismatch_policy": "warn"
  },
  "privacy": {
    "provider_store": "disable_when_supported",
    "data_collection": "deny_when_supported",
    "exact_location_exposure": "deny"
  }
}
```

字段规范：

- `language_tag`：BCP 47，例如 `en-US`。
- `country`：ISO 3166-1 alpha-2，例如 `US`。
- `timezone`：IANA 时区，例如 `America/New_York`。
- `currency`：ISO 4217，例如 `USD`。
- 日期、单位、货币不得只根据国家静默推断。可以生成建议值，但必须让用户确认并记录其来源。
- `location.precision` 第一版只允许 `none`、`country`、`region`、`city`。精确经纬度默认不进入提供商请求。
- 代理配置只保存不含凭据的引用；不得把代理用户名、密码或 URL 写入档案、日志或模型上下文。

身份信息使用独立模型，禁止放入 `EnvironmentProfile`：

```text
IdentityContext
├─ credential reference
├─ organization / project reference
├─ stable end-user identifier
└─ account policy
```

## 5. 生效值与优先级

每个字段必须保留“值、来源、发送方式和生效状态”，而不是只保留最终字符串：

```text
ResolvedValue
├─ value
├─ source: request | conversation | profile | app-default | system-opt-in
├─ delivery: native | semantic | local | transport | omitted
└─ status: applied | downgraded | unsupported | conflict
```

解析优先级：

```text
不可覆盖的安全规则
  > 单次请求显式覆盖
  > 会话固定档案
  > 用户选择的档案
  > Packagis 默认值
  > 经用户授权读取的系统值
  > 省略
```

冲突规则：

- 语言、国家、城市、时区、单位和货币分别解析，不能由一个国家值强制覆盖全部字段。
- 用户在正文中询问“东京天气”时，东京是任务目标，不自动成为用户位置。
- 原生位置字段与语义指令必须由同一个生效档案生成；两者冲突时默认报错。
- 会话开始后固定档案版本。中途切换时创建明确的环境变更记录，并重新生成当轮指令。
- 出口国家与档案预期不一致时只显示诊断；不通过伪造 HTTP 头消除差异。
- 凭据、组织、项目和稳定安全标识不参与地区优先级计算。

建议提供三种编译模式：

| 模式 | 行为 |
|---|---|
| `bestEffort` | 原生字段 → 语义指令 → 本地格式化 → 省略，并返回诊断；建议作为默认值 |
| `strict` | 正式字段不支持、值冲突或网络策略不满足时拒绝发送 |
| `minimal` | 只发送提供商正式支持的原生字段，不做语义降级 |

## 6. 请求处理流水线

```text
用户请求
  → Canonical Request
  → Profile Resolver
  → Locale Validator
  → Semantic Locale Composer
  → Provider Capability Adapter
  → Schema / Model Capability Gate
  → Credential Injector
  → Transport Router
  → Provider
  → Response Normalizer
  → Effective Environment Report
```

各层职责：

1. `Canonical Request` 保留原始消息、模型、工具和档案引用，不包含明文密钥。
2. `Profile Resolver` 逐字段求出生效值，并生成不可变的会话快照。
3. `Locale Validator` 校验 BCP 47、ISO 国家码、IANA 时区和货币代码。
4. `Semantic Locale Composer` 只从结构化字段生成受控指令，不接收任意自由文本模板。
5. `Provider Capability Adapter` 只产生目标 API 正式支持的字段。
6. `Capability Gate` 按 `provider + API surface + model + schema version` 过滤字段；未知能力不猜测。
7. `Credential Injector` 在最后一步附加真实认证信息，其他层无权读取或改写明文凭据。
8. `Transport Router` 使用系统网络、直连或明确配置的代理；默认继续使用 macOS 当前系统路线。
9. `Response Normalizer` 统一流式事件、引用和用量，不把“模型通常遵循”报告成“已保证”。
10. `Effective Environment Report` 展示实际映射和降级结果，但不展示秘密。

## 7. 语言和格式的最大化处理

### 7.1 模型语义层

语言、普通时区语境、日期、货币和单位通常没有通用 API 字段，应生成一段稳定的高优先级指令：

```text
Regional response preferences:
- Default response language: English (en-US).
- Use American spelling.
- Interpret otherwise-unqualified dates and times in America/New_York.
- Current local datetime: 2026-07-23T09:30:00-04:00
  (America/New_York).
- Prefer MM/DD/YYYY, 12-hour time, USD, and US customary units.
- An explicit user instruction for another language overrides the default
  response language.
- Do not infer residency, citizenship, legal jurisdiction, or account region
  from these presentation preferences.
```

适配位置：

- OpenAI Responses：`instructions`。
- OpenAI Chat Completions：`developer` message；仅在目标模型不支持时降级为 `system`。
- Anthropic Messages：顶层 `system`。
- OpenRouter Chat：`system` 或目标模型支持的 `developer` message。
- OpenRouter Responses：`instructions`。

实现要求：

- 环境指令与用户原文分别编码，不能改写用户消息。
- 每个请求只注入一次，不能随历史消息重复膨胀。
- 使用 `previous_response_id` 等状态链时仍要按目标 API 的继承规则重新应用环境指令。
- 当前本地时间在发送瞬间按 IANA 时区计算，同时发送 ISO 8601 offset 和时区名，以正确处理 DST。

### 7.2 本地确定性格式化

提示词不能保证所有格式完全正确，因此结构化结果应优先在本地处理：

- 内部时间统一保存为 UTC 或带 offset 的 ISO 8601；展示时使用档案时区。
- 工具参数使用规范化数值和单位；只在 UI 或最终展示层转换。
- 货币换算与货币格式分开：档案只负责格式，不凭空决定汇率。
- 日期、数字、列表排序和复数规则使用明确指定的 locale，不依赖 macOS 全局默认值。
- App UI 语言与模型回复语言分开设置，避免切换请求档案时意外切换整个 UI。

## 8. 地区字段的提供商映射

### 8.1 OpenAI Responses

普通请求没有通用的 `language`、`locale`、`country`、`timezone` 或经纬度顶层字段。

Web Search 的正式映射：

```json
{
  "tools": [
    {
      "type": "web_search",
      "user_location": {
        "type": "approximate",
        "country": "US",
        "region": "New York",
        "city": "New York",
        "timezone": "America/New_York"
      }
    }
  ]
}
```

该字段只用于改进搜索结果的地区相关性，不改变网络来源、账号国家或账单地区。Deep Research 模型使用 Web Search 时不支持该位置参数。

`safety_identifier` 由独立身份层提供，必须是稳定且隐私保护的最终用户标识，不能随地区档案变化。

参考：

- [OpenAI Web Search：User location](https://developers.openai.com/api/docs/guides/tools-web-search#user-location)
- [OpenAI Safety identifiers](https://developers.openai.com/api/docs/guides/safety-checks#implementing-safety-identifiers-for-individual-users)
- [OpenAI API request ID](https://developers.openai.com/api/reference/overview#supplying-your-own-request-id-with-x-client-request-id)

### 8.2 Anthropic Messages

语言与格式映射到 `system`。Web Search 的正式位置映射：

```json
{
  "tools": [
    {
      "type": "web_search_20260318",
      "name": "web_search",
      "user_location": {
        "type": "approximate",
        "country": "US",
        "region": "New York",
        "city": "New York",
        "timezone": "America/New_York"
      }
    }
  ]
}
```

必须至少提供城市、地区、国家或时区之一；国家使用两位 ISO 代码，时区使用 IANA 名称，不支持经纬度。

`inference_geo` 是单独的数据处理区域能力。目前受支持的值、模型和账户条件必须由能力矩阵确认；它不能被解释为用户位置。

`metadata.user_id` 属于稳定的最终用户标识，不属于地区档案。

参考：

- [Anthropic Web Search localization](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)
- [Anthropic Messages API](https://platform.claude.com/docs/en/api/typescript/messages/create)
- [Anthropic Data residency](https://platform.claude.com/docs/en/manage-claude/data-residency)

### 8.3 OpenRouter

语言和格式映射到 Chat 的高优先级 message 或 Responses 的 `instructions`。

推荐的 Web Search Server Tool 映射：

```json
{
  "tools": [
    {
      "type": "openrouter:web_search",
      "parameters": {
        "engine": "native",
        "user_location": {
          "type": "approximate",
          "country": "US",
          "region": "New York",
          "city": "New York",
          "timezone": "America/New_York"
        }
      }
    }
  ]
}
```

重要限制：

- Server Tool 当前是 Beta。
- `user_location` 当前只对 native provider search 生效。
- Exa、Firecrawl、Parallel 和 Perplexity 会忽略该位置。
- 旧 `plugins: [{"id":"web"}]` 和 `:online` 方式已经被文档标记为 deprecated。

时区还可映射给 Datetime Server Tool：

```json
{
  "type": "openrouter:datetime",
  "parameters": {
    "timezone": "America/New_York"
  }
}
```

这只是为模型提供对应时区的当前时间，不改变账号或网络环境。

OpenRouter 的 `provider` 对象可以控制：

- `order`、`only`、`ignore`、`allow_fallbacks`
- `require_parameters`
- `data_collection`
- `zdr`

它没有任意的 `provider.country`。EU in-region routing 是单独的 Enterprise 能力，不等于用户地区设置。

建议地区搜索请求启用 `provider.require_parameters: true`，避免路由到不支持所需参数的 endpoint；同时仍要检查最终路由报告。

参考：

- [OpenRouter Web Search Server Tool](https://openrouter.ai/docs/guides/features/server-tools/web-search)
- [OpenRouter Datetime Server Tool](https://openrouter.ai/docs/guides/features/server-tools/datetime)
- [OpenRouter Provider Routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [OpenRouter ZDR](https://openrouter.ai/docs/guides/features/zdr)
- [OpenRouter EU in-region routing](https://openrouter.ai/docs/guides/privacy/provider-logging)

## 9. HTTP 与网络层

### 9.1 HTTP 头

- `Authorization`、`x-api-key`、组织和项目头只表达真实身份与计费归属。
- `Accept-Language` 可作为通用 HTTP 偏好在明确支持它的 endpoint 上启用，但 OpenAI、Anthropic 和 OpenRouter 的核心推理 API 没有把它定义为模型语言或位置控制字段；默认不依赖它。
- `User-Agent` 应真实标识 Packagis 及版本，不伪装成浏览器或其他设备。
- OpenRouter 的 `HTTP-Referer`、`X-OpenRouter-Title` 是真实 App Attribution，不是用户位置。
- 禁止构造或覆盖 `Forwarded`、`X-Forwarded-For`、`CF-Connecting-IP`、`True-Client-IP` 等来源头。

### 9.2 Shadowrocket

默认的 `network.route = system` 表示 Packagis 使用 macOS 当前网络路线。Shadowrocket 若通过系统代理或 TUN 接管流量，Packagis 的请求会按实际配置经过它：

```text
Packagis
  → macOS 网络栈
  → Shadowrocket
  → VPN / 代理出口
  → OpenRouter / OpenAI / Anthropic
```

Packagis 不需要位于 TLS 链路中间，也不需要解密自己的请求，因为它在加密前已经拥有结构化请求。

可选的出口诊断应使用与模型请求相同的网络会话，只记录：

- 当前观测到的出口国家和大致地区。
- 与 `expected_exit_country` 是否一致。
- 检查时间、数据源和置信度。

不得把 IP 地址、代理凭据或精确位置写入普通日志。代理失败时默认失败关闭，不静默改为直连；是否允许 fallback 必须由用户明确设置。

## 10. 隐私和安全不变量

1. API Key、代理凭据和账号标识永不进入提示词、请求诊断或日志。
2. 切换地区档案不得改变凭据、组织、项目、账单身份或稳定安全标识。
3. `safety_identifier`、`user`、`metadata.user_id` 使用稳定的匿名值，不随地区切换。
4. 不自动读取 macOS 精确定位；精确位置必须逐次授权，并且只发给正式支持且确有任务需要的 endpoint。
5. 默认发送完成任务所需的最低位置精度。
6. 不把坐标塞进 prompt 或 metadata 来绕过不支持的 schema。
7. `store`、ZDR 和 data collection 使用独立隐私策略，不由国家档案隐式决定。
8. 只允许提供商 adapter 输出白名单字段和头，禁止任意 JSON/HTTP 头注入。
9. Profile 名称、城市和地区文本必须防止 CRLF、JSON 和提示词注入。
10. 保持 HTTPS 端到端，不通过 MITM 控制其他桌面 App。
11. UI 必须显示“请求的环境”和“实际生效环境”，不能宣传为完整身份替换。

## 11. 生效报告

当前 `PreparationReport` 已能随 prepared request 返回以下子集：

| 维度 | 发送方式 | 当前结果 |
|---|---|---|
| 回复语言 | provider 高优先级指令 | `applied` |
| 时区 | 语义指令与请求时本地时间 | `applied` |
| 搜索地点 | Web Search 原生字段 | OpenAI/Anthropic 为 `applied`；OpenRouter 为 `providerDependent` |
| provider storage/privacy | 正式支持的 request 字段 | `applied` 或 `unsupported` |

出口国家、实际路由、推理区域和账号能力尚未观测。未来诊断视图可以扩展
`source`、网络实测与冲突信息，但不能把请求值当作实际生效证据。

报告不能显示 API Key、完整代理 URL、提示词全文、附件内容、精确坐标或个人身份信息。

## 12. 第一版验收矩阵

| 维度 | 必测情况 |
|---|---|
| Provider | OpenAI Responses、OpenAI Chat、Anthropic Messages、OpenRouter Chat/Responses |
| Profile | `en-US/US/New_York`、`zh-CN/CN/Shanghai`、字段部分缺失、故意冲突 |
| 时间 | DST 切换前后、无 DST 地区、无效 IANA 时区 |
| 地点 | 国家级、城市级、Unicode 城市名、非法国家码、精确坐标被拒绝 |
| 内容 | 文本、文件、工具调用、Structured Output、流式 |
| 冲突 | 请求覆盖、会话固定值、Profile、原始原生字段之间的冲突 |
| 网络 | Shadowrocket 系统路线、代理失效、出口不匹配、禁止静默直连 |
| 隐私 | `store`、ZDR、data collection、日志脱敏、附件元数据 |
| 身份 | 切换多个地区后凭据和稳定安全标识保持不变 |
| 降级 | 原生 → 语义、本地格式化、字段不支持、未知模型严格失败 |
| 安全 | CRLF、恶意城市名、Profile 提示词注入、代理 URL 泄漏 |

关键断言：

- 同一环境字段不会被重复注入。
- Web Search 位置只出现在支持的位置结构中。
- 不支持经纬度的目标不会收到经纬度。
- 原始用户消息保持字节级或结构级不变。
- 环境档案切换不改变身份字段。
- 请求实际走过的网络路线与生效报告一致。
- 未知提供商或模型不会收到猜测出来的字段。
- 日志、快照和错误信息不包含秘密。

## 13. 实施顺序

1. `EnvironmentProfile` 与校验器已实现；会话快照未实现。
2. Semantic Locale Composer 已实现；结构化本地格式化未实现。
3. OpenAI Responses adapter 已实现。
4. Anthropic Messages 和 OpenRouter Chat adapters 已实现。
5. Shadowrocket/system route 的只读出口诊断未实现。
6. `PreparationReport` 子集已实现；完整 Effective Environment Report 未实现。
7. 自有 CLI 子进程环境与显式代理模式尚未决定。

第一版不需要实现 Chrome 浏览器 API patch，也不直接复用 GeoMirror 的 MAIN-world 注入方式。可以复用的思想是：同一个规范化档案生成语言、时区、地点和请求策略；不可复用的部分是浏览器指纹覆盖、定位权限伪装和字体探测。GeoMirror 对自身边界的说明见其 [中文 README](https://github.com/Azurboy/geomirror/blob/main/README.zh-CN.md)。
