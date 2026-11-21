# 后端 API 变更说明（2026-11-21 · 第二轮）

补第一轮遗漏，并回应 iOS 编辑频道页截图反馈。

验证依据：后端测试 85/85 通过；生产数据副本逐项打真实请求（15/15）。

---

## 一、后端已改（3 项）

### A45 频道 DTO 现在带连接器名称

**你截图里一屏 UUID 的原因**：`channel()` 只返回 `connectorIds` 这个 UUID 数组，从未返回名称。

现在每个 Channel 对象额外含 `connectors`，结构与 `GET /api/v1/connectors` 一致：

```json
{
  "id": "chn_…",
  "name": "安全频道",
  "connectorIds": ["b5abd909-8bad-43e2-bcd3-b9b0a3d9838d"],
  "connectors": [
    { "id": "b5abd909-8bad-43e2-bcd3-b9b0a3d9838d", "name": "HN 首页", "kind": "hn", "removed": false }
  ]
}
```

- `connectorIds` **保留**，兼容你现有解析
- `removed: true` 表示该连接器已从后端代码移除，但仍给 `name` —— 你可以据此显示「HN 首页（已失效）」而不是裸 UUID
- 极少数情况下后端完全查不到该 id（数据不一致），返回 `{ id, name: null, kind: null, removed: true }`，需要你兜底文案

**前端动作**：直接用 `connectors[].name` 渲染，删掉 UUID 显示逻辑。

### A46 连接器可由用户增删（后端本来就支持，是契约没写清）

`PATCH /api/v1/channels/:id` 的 `connectorIds` 一直是可写的，传数组就是**整体替换**：

```json
PATCH /api/v1/channels/chn_xxx
{ "connectorIds": ["id-a", "id-b"] }   // 替换为这两个
{ "connectorIds": [] }                  // 清空，不启用任何连接器
```

- 数组里含不可用（未启用或已从代码移除）的 id → `400 { "code": "invalid_connector" }`，**且不会修改**
- 可用集合从 `GET /api/v1/connectors` 取
- 频道有运行在跑时 `PATCH` 返回 `409 busy`

**前端动作**：把「Read-only / Connectors can't be changed on mobile — edit them in the admin console」**删掉**，改成可编辑列表 + 「+ 添加连接器」（数据源 `GET /api/v1/connectors`）。

### A47 无预设也能创建频道

新增：

```
POST /api/v1/channels
Content-Type: application/json

{
  "name": "我的频道",
  "prompt": "追踪 AI 进展",
  "tone": "冷静、具体",
  "schedule": { "mon": ["08:00", "20:00"], "fri": ["09:30"] },
  "connectorIds": ["b5ab…"],
  "enabled": true
}
→ 201 返回完整 Channel 对象
```

- `kind` **固定为 `channel`**，客户端传 `kind: "preset"` 会被忽略（用户不能自建预设）
- 缺 `name` 或 `prompt` → `400 invalid_input`
- `connectorIds` 非法 → `400 invalid_connector`
- `schedule` 结构错误 → `400 invalid_input`
- `schedule` 支持**同一天多个时刻**（见下面第 3 点）

**前端动作**：`+` 入口现在可以真的建频道了，不再需要「没有预设」的提示。

---

## 二、你截图中纯 UI 问题（后端无改动，但确认数据侧支持）

### 1. 返回箭头与 Cancel 按钮重复

导航栏已有 `<` 返回，中间又放 `Cancel`，两者语义相同。

**建议**：删掉 `Cancel`，保留左箭头；或把左箭头去掉只留 `Cancel`。二选一即可，后端无关。

### 2. 连接器「Read-only」标注

如 A46 所述，连接器**不是只读的**。这个标注源于后端契约没写清，现在已补。请一并去掉该标注和底部那句
「Connectors can't be changed on mobile — edit them in the admin console」。

### 3. 时间选择器排版

**后端数据结构天生支持一天多个时刻**，不需要改：

```json
{ "mon": ["01:25", "08:00", "20:00"], "fri": ["09:30"] }
```

你截图里每天只渲染了一个时间槽，是前端布局问题。建议结构：

```
Schedule
┌ 周一 ─────────────────────────┐
│  [01:25] ✕   [08:00] ✕   [+ 添加时间] │
└───────────────────────────────┘
┌ 周二 ─────────────────────────┐
│  [01:25] ✕   [+ 添加时间]        │
└───────────────────────────────┘
...
```

要点：
- 「+ 添加时间」在**每一天内部**，不是全局
- 每个时刻可单独删除
- 某天全部删完就是 `[]`，后端接受「该天不采集」
- 星期标签建议用短名（Mon/Tue…），截图里 `Wednesday`/`Saturday` 换行断字了

**提交时**：把每天的时间数组直接放进 `schedule` 的对应 key，后端会去重排序。

---

## 二·补 又补了两项（原文档「仍未处理」里的前两条）

### A48 手机端可以删除频道了

```
DELETE /api/v1/channels/chn_xxx
Authorization: Bearer <会话凭证>

→ 200 { "id": "chn_xxx", "deleted": true }
```

- **软删除**：频道从列表、详情、日报、运行、`/cursor` 全部消失，但**日报/运行/素材记录仍在库中**可审计
- 删除别人的频道 → `404`
- 重复删除 → `404`
- 有运行在跑 (`queued/collecting/writing`) → `409 busy { code: "busy" }`
- 成功会写审计日志

**前端动作**：频道列表可以加左滑删除 / 长按菜单，调这个端点即可。删除后本地缓存要移除该频道。

### A49 可以读取时区了

```
GET /api/v1/settings
→ 200 { "timeZone": "Asia/Shanghai" }
```

- 只读，无写接口（传 `POST` 会 `404`）
- **只返回客户端需要的项**，不暴露 `maxTotal/maxCollectors` 这些管理端参数
- 时区由管理员在后台配置；配置非法时回退 `Asia/Shanghai`

**前端动作**：截图底部那句「Interpreted in Asia/Shanghai」现在可以动态渲染了——取 `settings.timeZone` 填进去，管理员改时区后客户端跟着变。

## 三、附带说明

**时区**：截图底部提示「Interpreted in Asia/Shanghai」。这个值由管理员在后台设置页配置（任意 IANA 名），
客户端用 `GET /api/v1/settings` 读取，见上面 A49。

**本轮之后仍未处理**：
- `Ask` 不接 LLM（`deterministic: true` 已标注，但会给 `citedItemIds`）
- 「活跃频道至少一个连接器」未强制校验，建频道时请自选
- `PUT` 等未实现方法返回 `404` 而非 `405`

完整契约见后端仓库 `API.md`。
