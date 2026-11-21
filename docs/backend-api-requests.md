# 客户端需要后端完善/修复的接口清单

来源：iOS 客户端（`reachnews-client`）重构过程中实测 + 后端源码核对。
核对方式：只读 `src/server.mjs` / `src/domain.mjs` / `src/db.mjs`，并在 `/tmp` 起临时 DB 实例打真实 HTTP 请求。
**未修改后端任何文件。**

优先级说明：P0 = 会让客户端界面出错；P1 = 影响体验或能力缺失；P2 = 一致性与可维护性。

---

## P0｜`/cursor` 的 `briefs` 泄漏已删除频道的日报

**现状（源码依据）**：`src/server.mjs:546` 的 `/api/v1/cursor` 中，`channels` 子查询带了 `deleted_at IS NULL`，但 `briefs` 子查询只 `JOIN channels c ON c.id=b.channel_id WHERE c.user_id=? AND b.created_at>?`，**没有 `deleted_at` 过滤**。
实测：软删除一个频道后，`/cursor?since=` 的 `briefs` 仍返回该频道的日报。

**对客户端的影响**：客户端把 `cursor.briefs` 视为「新内容」用于标注与合并。已删频道的日报进入信息流后，客户端按 `channelId` 找不到频道，会渲染成无频道名的孤儿行。

**期望**：`briefs` 子查询补 `AND c.deleted_at IS NULL`。

**验收**：删除频道后，`/cursor.briefs` 不再包含该频道任何日报。

---

## P0｜preset 频道会产出日报，但客户端列表看不到它

**现状（源码依据）**：`kind='preset'` 的频道是普通 channel 行，`createChannel` 默认 `enabled=1`；`dueChannels` **不按 `kind` 过滤**，实测周一 09:00 的 due 列表同时含 `follow` 与 `preset`。
因此 preset 会被调度、产出 brief，并出现在 owner 的 `/cursor.briefs` 与各频道日报端点里。

**对客户端的影响**：客户端已按「preset 是管理员模板、普通用户不展示」把 preset 从频道字典中剔除（`ChannelKind.isUserVisible`）。结果就是**必然出现找不到频道的孤儿日报**。

**期望（需产品定取舍，倾向 A）**：
- **A（推荐）**：`dueChannels` 加 `kind != 'preset'` —— preset 只作模板，不参与调度。
- B：`/cursor` 与 `/channels` 对普通用户过滤 `kind='preset'`；但 preset 若仍调度，孤儿日报问题只是从列表转移到信息流。

**若采纳 A**，还需一并处理：
- `PATCH /channels/:id` 与 `POST /channels/:id/run` 目前只校验 `user_id`，不校验 `kind`，实测 owner 可直接改/触发 preset → 需加 `kind != 'preset'` 守卫。

**验收**：普通用户的信息流与频道列表互相对得上，不存在找不到频道的日报。

---

## P1｜日报级与运行级端点未过滤软删除频道

**现状（源码依据）**：软删除只过滤了**频道级**端点（列表、详情、`briefs` 列表、`runs` 列表、`PATCH`、`run`），实测均正确 404。
但**日报级与运行级**端点只 JOIN `channels c ... c.user_id=?`，缺 `c.deleted_at IS NULL`：

| 端点 | 对已删频道实测 |
|---|---|
| `GET /api/v1/briefs/:id` | 200 |
| `GET /api/v1/briefs/:id/items/:itemId` | 200 |
| `GET\|POST /api/v1/briefs/:id/ask` | 200 / 201 |
| `POST /api/v1/briefs/:id/regenerate` | 202 |
| `POST /api/v1/follows {sourceBriefId}` | 201 |
| `POST /api/v1/runs/:id/retry` | 202（并新建 run） |
| `POST /api/v1/runs/:id/resume` | 202（并新建 run） |

实测删除频道后出现 `retry` / `resume` / `regenerate` / `failure-retry` 四个新 run。`publishBrief` 也不校验频道是否已删。

**对客户端的影响**：客户端目前以「频道列表」为准判断可达性，所以不会主动请求已删频道；但若从收藏或历史链接进入，仍可能拿到 200 并展示已删频道的日报。

**期望**：抽一个 `liveBrief(db, briefId, userId)` 之类的帮助函数，统一给日报级/运行级查询加 `deleted_at IS NULL` 过滤。**新增的全量日报端点也必须带该过滤。**

**验收**：删除频道后，该频道所有日报与运行相关端点一律 404。

---

## P1｜没有全量日报端点，首屏是 N 个请求

**现状**：`/api/v1` 下不存在 `GET /api/v1/briefs`（实测 404）。客户端只能 `GET /channels/:id/briefs` 逐频道取。

**对客户端的影响**：日报页是「全部历史」视图，首屏 = 频道数 × 1 请求；翻页时每个频道再各取一页，且要为每个频道单独维护游标。频道一多明显变慢，分页逻辑也容易漂移。

**期望**：新增 `GET /api/v1/briefs?cursor=<offset>&limit=<n>`，跨频道按 `created_at DESC, id DESC` 返回 `{items, nextCursor}`，复用现有 `cursorPage`。

SQL 参考：
```sql
SELECT b.*, c.name AS channelName, c.kind AS channelKind
FROM briefs b JOIN channels c ON c.id = b.channel_id
WHERE c.user_id = ? AND c.deleted_at IS NULL
ORDER BY b.created_at DESC, b.id DESC
```
`brief()` DTO（`server.mjs:74`）可选增加 `channelName` / `channelKind`，减少客户端 fan-out 后仍需查频道的需要。

**注意**：`ORDER BY` **必须带 `id` tie-breaker**。现有 `test/rules.test.mjs:151` 已因同一毫秒内 `created_at` 打平而偶发失败（连跑 5 次有 2 次失败）；跨频道分页若不带 tie-breaker 会重复/漏项。

**验收**：一次请求拿到跨频道最新 N 期，含 `channelId`；深分页不重复不遗漏。

---

## P1｜负 `cursor` 会从尾部倒序返回数据（比“空页”更严重）

**现状（源码依据）**：`src/domain.mjs:149`：

```js
const offset = Number.parseInt(cursor || "0", 10) || 0;
return { items: rows.slice(offset, offset + size),
         nextCursor: offset + size < rows.length ? String(offset + size) : null };
```

负值不拦截。实测真值表（临时实例）：

| 数据 | 传入 | 返回 |
|---|---|---|
| len=40 | `cursor=-5, limit=20` | items=0, next=`"15"` |
| len=40 | `cursor=-5, limit=2` | **返回索引 35、36**, next=`"-3"` |
| len=3 | `cursor=-5, limit=20` | items=3（取到尾部）, next=null |
| len=40 | `cursor=-1, limit=2` | 空, next=`"1"` |

即 `slice` 的负索引语义让它**从尾部读数据**，而不是越界空页；`nextCursor` 又用未 clamp 的 `offset` 计算，负游标会持续传播。

**对客户端的影响**：客户端已防御性丢弃负 `cursor`、也从不发送负值。但任何第三方消费者都会踩。

**期望**（二选一，不要两处都改）：
- 在 `cursorPage` 里 `offset = Math.max(0, Number.parseInt(cursor) || 0)`，且 `nextCursor` 用 clamp 后的 offset；
- 或在 `pageFrom`（`server.mjs:65`）对 `cursor < 0` 返回 `400 invalid_input`。

**附带**：`cursorPage` 目前**没有任何单测**，建议补真值表用例。

**验收**：负 `cursor` 不再返回数据，也不再产生负 `nextCursor`。

---

## P2｜`/ask` 不返回引用了哪些素材

**现状**：`POST /api/v1/briefs/:id/ask` 响应字段恰为 `{message, answer}`，`answer` 是确定性拼接：
`已基于「{title}」的归档摘要记录问题：{message}。当前可用摘要：{memory_summary}`。

**对客户端的影响**：视觉稿要求一条「引用的素材 · N 条」内嵌卡，现在只能标「功能开发中」，无法落地。

**期望**：响应增加 `citedItemIds: string[]`。素材归属本来就存在于该 brief 的 `sections[].items[].itemIds`，无需新查询，汇总去重即可。建议同时在 `answer` 文本或字段中注明「确定性应答；引用为本期素材」。

**验收**：客户端能把 `citedItemIds` 映射到素材并渲染引用卡；现有仅断言 `answer` 是 string 的测试不因此失败。

---

## P2｜无法枚举连接器，手机端不能创建频道

**现状**：`GET /api/v1/connectors` 与 `/api/v1/presets` 实测 404；`POST /api/v1/channels`、`DELETE /api/v1/channels/:id` 也 404。连接器只能在 `/admin/api/connectors`（管理员 Cookie）枚举。

**对客户端的影响**：手机端创建的频道必然 `connectorIds: []`，启用后每次运行都 `missed`（`no-material`）。ADR 0004 因此决定暂不提供创建保存，`+` 入口只提示不可用。

**期望**：新增 `GET /api/v1/connectors`，返回 `{id, name, kind}`。
**不要返回 `config`** —— `connector-catalog.mjs` 的 config 含 `headers`，有凭证泄漏风险。
SQL：`SELECT id, name, kind FROM connectors WHERE enabled = 1 AND removed = 0`。

**另外**：`POST /api/v1/follows` 目前不校验 `connectorIds` 是否存在，实测传 `["does-not-exist"]` 仍 201 建成频道，又回到「建出来必 missed」。建议校验 id 必须落在可用连接器集合内，否则 400 `invalid_connector`。

**验收**：客户端能选择连接器创建频道，且建出的频道能实际产出日报。

---

## P2｜`/cursor` 与 `/ask` 历史的字段风格与主体端点不一致

**现状**：`/cursor` 与 `/ask` 历史用 `snake_case`，`/cursor` 的 `enabled` 是整数 `1/0`；其余端点为 camelCase + 布尔。

**对客户端的影响**：DTO 层要维护两套解析（已实现并各有单测），容易出错。

**期望**：统一为 camelCase + 布尔。若担心破坏兼容，可加 `?version=2` 或新端点，但请明确取舍。

**验收**：客户端可删除 `FlexibleBool` 与 snake_case 映射。

---

## P2｜`POST /runs/:id/retry` 返回 `queued: {}`

**现状**：`runEngine.drain(1)` 是 `async`，handler 里 `const result = runEngine.drain(1)` 未 `await`，Promise 被序列化成 `{}`。`regenerate` 同样。

**期望**：`await runEngine.drain(1)`，或直接删掉这个字段。

**验收**：返回值不再是空对象。

---

## 文档需要同步（API.md 与源码不符）

1. **API.md:24 / :29 过度承诺**：声称「所有频道相关端点只返回未删除频道」「该行为已修正」。实际只有**频道级**端点过滤了；**日报级与运行级**未过滤（见 P1 第一条）。请按真实范围改写。
2. **API.md:251 已知缺口第 1 条**：应明确「手机端也不能**删除**频道」（现在口径分散在第 7 条）。
3. **API.md:261 第 8 条**：负 cursor 的描述应写真实后果——「负值会从尾部倒序返回数据」，而不只是「返回空页」。
4. **`kind` 取值**：需写明已扩为 `channel | follow | preset`，并说明 preset 是否参与调度（取决于 P0 第二条的取舍）。

---

## 客户端侧已做的防御（供后端参考，不要求后端迁就）

- 丢弃负 `cursor`、从不发送负值或越界 `limit`。
- `missedReason` 与 `error.code` 的未知值保留原始字符串。
- `FlexibleBool` 同时接受 `1/0` 与 `true/false`。
- preset 频道不进入客户端频道列表。
- 429 不自动重试（避免续期锁定）。
