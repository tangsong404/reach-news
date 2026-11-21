# 客户端契约

> 服务端的实测契约以 [API.md](/var/lib/dsh/reach-news/API.md) 为权威。本文件只补客户端侧约束：状态映射、空态、错误归一化、分页与轮询规则、以及必须遵守的字段处理方式。两者冲突时以 API.md 为准，并回头修本文件。

## 术语

见 [GLOSSARY.md](/GLOSSARY.md)。注意区分：日报 payload 里的 `sections[].items[]` 是**条目**，`itemId` 指向的原始内容是**素材**。两者不可混称。

## 字段归一化（进入客户端边界时一次完成）

| 远端形状 | 客户端形状 | 说明 |
|---|---|---|
| `/cursor` 与 `/ask` 历史的 `snake_case` | camelCase | 在 DTO 层转换，UI 只见 camelCase |
| `/cursor` 的 `enabled: 1 \| 0` | `Bool` | 整数与布尔混用，不可直接传下去 |
| 时间戳 `2026-11-20T02:01:50.774Z` | `Date`（UTC） + 展示时转 `Asia/Shanghai` | 不存储格式化字符串 |
| `missedReason` 任意字符串 | 枚举 + `.unknown(String)` | 服务端会新增原因，未知值不得丢弃 |
| `error.code` | 枚举 + `.unknown` | 已实测：`unauthorized` `not_found` `invalid_input` `busy` `bad_request` `internal_error` `too_many_attempts` |

`not_found` 有两义（端点不存在 / 资源不存在），只能靠请求路径区分，不得用 code 推断。

## 状态三分法

| 状态 | 是否产出日报 | 呈现 | 可用动作 |
|---|---|---|---|
| `queued` `collecting` `writing` | 否 | 轻量进行中指示 | 无 |
| `published` | 是 | 不显示任何运行装置，只有日报 | 「重新生成」（见 ADR 0004：等运行级端点） |
| `missed` | 否 | 中性色，「本次未产出日报」 | 无（等运行级端点） |
| `failed` | 否，但素材保留 | 警示色，「运行失败，素材已保留」 | 等运行级端点 |
| `cancelled` | — | 不实现 | 服务端无路径会进入此状态，不要做取消按钮 |

`missed` 不是失败。`missedReason` 已知有 `no-material`（采集完零素材）与 `queue-timeout`（到点未启动）；二者都不提供「重试」，因为 `no-material` 是配置问题而非故障。

## 分页

- `?cursor=<整数偏移>&limit=<n>`，`limit` 缺省/0/非数字 → 20，负数 → 1，>100 → 100。
- **不要传负值**，**不要缓存负 `cursor`**（`cursor=-5` 返回空页却给出非空 `nextCursor`，属服务端缺陷）。
- 列表按 `created_at DESC`，写入会移动偏移，因此深分页不稳定：翻页只用于向后滚动，去重与「是否有新内容」一律靠 ID 集合与 `lastSeenAt`，不靠偏移。

## 轮询

- 无 SSE/WebSocket/推送（服务端明确不做）。
- 进入日报页拉一次 `GET /api/v1/cursor?since=<lastSeenAt>`；停留期间每 60 秒一次；下拉刷新额外触发；离开页面即停。
- `since` 严格大于比较；无 `since` 回落到 1970 年即全量，**必须总是带 `since`**。
- 返回的 `briefs` 视为「新内容」用于标注，`channels` 视为「配置被改动」用于刷新频道列表。
- 推进 `lastSeenAt` 时取响应中最大的 `created_at`，而不是本地当前时间（避免时钟偏差吞掉内容）。
- 没有批量运行状态端点，观察 N 个频道需逐个 `GET /runs/:id`，因此只在频道页对**可见行**轮询。

## 空态与不可用能力

| 情形 | 处理 |
|---|---|
| 无频道 | 说明频道由管理员开通；不提供无效的「新建」入口 |
| 频道 `connectorIds` 为空且 `enabled` | 提示「未配置连接器，运行将不会产出日报」 |
| 频道 `kind: "preset"` | 管理员模板频道，会参与调度；普通用户列表不展示 |
| 频道运行中（`queued`/`collecting`/`writing`）改配置 | 服务端返回 `409 busy`，保留已填内容并提示稍后 |
| 断网 | 直接提示当前无网络，不展示缓存内容（见 ADR 0003） |
| 素材 `content` | **永不渲染**。RSS 为原始 XML、GitHub 为原始 JSON 字符串。只显示 `title`、来源域名、`url` 外开 |
| `ask` 的回答 | 当前是确定性字符串拼接，不是 LLM。不得设计流式、打字机或「正在思考」 |

## 鉴权

后端已改为账号密码换取短期会话凭证。**旧的长期 Bearer Token 已全部失效，这是硬切换、没有兼容期。**

- `POST /api/v1/login`（唯一无需凭证的端点）`{username, password}` → `200 {token, expiresAt, user}`，凭证明文不落日志。
- 请求体必须是 JSON；form-encoded 会得到 `500 internal_error`（只有 `/login` 这样）。
- 凭据错误 `401 unauthorized`，**不区分「用户不存在」与「密码错误」**，不要据此提示具体原因。
- 限流：同一用户名 5 分钟内累计 5 次失败后，第 6 次起 `429 too_many_attempts`，**期间正确密码也会被拒**；每个被拦请求仍计一次失败，因此**客户端绝不能自动重试**，否则一直延长锁定。没有 `Retry-After`，需自行冷却。
- 会话有效期 7 天，服务端按 `expires_at` 校验。**没有 refresh 接口**，过期即重新登录。
- `POST /api/v1/logout` 需凭证，返回 `200 {ok:true}`；无论结果如何，客户端都应立即清本地凭证。
- 管理员重置密码会清空该用户全部会话 → 客户端收到 401 应回登录页，不要无限重试。
- 手机端凭证 `scope=mobile`，打 `/admin/*` 与 `/admin/api/*` 一律被拒（302/401），不要尝试。
- Base URL 预填 `reachapi.niuma.art`，允许编辑以便本地调试。

## Fixture

`Fixtures/*.json` 存放真实形状的样本（频道、日报、条目、素材、运行、`/cursor`、错误），同时供 SwiftUI Preview 与单元测试使用。样本必须覆盖：`lastBriefAt: null`、`connectorIds: []`、`missed` + `no-material`、`failed`、`sections` 多分组、条目引用多个素材。
