# iOS 客户端完整规格

本 capability 描述重构后 iOS 客户端在归档时应具备的完整行为。数据来自 `reachapi.niuma.art` 的 `/api/v1`，界面依据 `design/mockups/v2.html`，行为约束来自 `docs/client-contract.md`、`docs/adr/` 与 `GLOSSARY.md`。

## 领域模型

客户端在与服务端边界处一次性完成归一化，内部只使用本节的类型与命名。术语严格遵循 `GLOSSARY.md`：`items` 在日报 payload 里是**条目**（`Entry`），`itemId` 指向的是**素材**（`Material`），两者不可混称。

- `Channel`：`id`、`name`、`prompt`、`tone`、`schedule: Schedule`、`enabled: Bool`、`connectorIDs: [String]`、`lastBriefAt: Date?`、`kind: ChannelKind`、`published: Bool`、`owner: ChannelOwner`、`subscribed: Bool`、`subscriptionColor: String?`、`subscriptionID: String?`、`createdAt`、`updatedAt`。
- `ChannelKind`：`.channel` / `.follow`。`follow` 显示「跟踪」徽标。服务端已无 `preset`；解析到 `preset` 或任何未知值时一律降级为 `.channel`。`kind` 只区分「用户频道」与「跟踪」，与订阅无关，可写性判定不得使用它。
- `ChannelOwner`：`.creator` / `.subscriber`，表示当前用户相对该频道的身份。
- `Channel` 的派生判定（唯一正确写法）：`canEdit = owner == .creator`、`canSubscribe = published && owner != .creator && !subscribed`、`canUnsubscribe = subscribed`。
- `subscriptionColor` 可为 `null`（未订阅）或空字符串（订阅时未给颜色）；两者在客户端都按「未设置」处理，不显示空色点。
- 订阅是「用户 × 频道」上的一条关系，不是频道对象，也不是一种 `kind`；订阅频道的 `id` 就是原频道的 `id`，列表中不出现副本条目。
- `Schedule`：周一到周日各可配零到多个 `HH:MM`；未配置的星期视为无触发。所有时刻按 `Asia/Shanghai` 解释。
- `Brief`：`id`、`channelID`、`title`、`summary: String?`、`body: BriefBody?`、`sections: [BriefSection]`、`memorySummary`、`createdAt: Date`。
- `BriefBody`：`paragraphs: [BriefParagraph]`。`body` 为精写成稿，可为 `nil`。
- `BriefParagraph`：`segments: [BriefSegment]`。
- `BriefSegment`：`.text(String)` 或 `.link(text: String, url: URL, itemID: String?)`。`itemID` 只用于定位原文，不参与业务判断。
- `summary` 是这一期给读者的描述，可为 `nil`；`memorySummary` 是运行记忆，**不在任何界面展示**，两者不可混用。
- 频道展示名一律用 `name`：服务端已移除 `title` / `description` / `displayTitle`，客户端不得读取或回退到这三个字段。
- `BriefSection`：`title`、`entries: [Entry]`。
- `Entry`：`title`、`summary`、`materialIDs: [String]`。
- `Material`：`id`、`title`、`url: URL`、`publishedAt: Date?`、`metadata`、`content`。`content` 只解析不展示。
- `Run`：`id`、`state: RunState`、`trigger`、`startedAt: Date?`、`finishedAt: Date?`、`missedReason: MissedReason?`、`createdAt`。
- `AskTurn`：`id`、`role: .user/.assistant`、`message`、`createdAt`。
- `CursorPayload`：`briefs: [CursorBrief]`、`channels: [CursorChannel]`；`CursorChannel.enabled` 为 `Bool`。

## 字段归一化

DTO 层一次完成，UI 与 Store 只见归一化后的类型：

- `/cursor` 与 `/ask` 历史的 `snake_case` 字段名转为 camelCase。
- `/cursor` 的 `enabled: 1 | 0` 转为 `Bool`。
- 所有时间戳按 UTC ISO 8601 带毫秒解析为 `Date`；展示时转 `Asia/Shanghai`。不存储格式化字符串。
- `missedReason` 归一化为 `.noMaterial` / `.queueTimeout` / `.resumeWriting` / `.unknown(String)`；未知值保留原始字符串，不丢弃。
- `error.code` 归一化为 `.unauthorized` / `.tooManyAttempts` / `.invalidConnector` / `.notFound` / `.invalidInput` / `.busy` / `.badRequest` / `.internalError` / `.presetsRemoved` / `.notPublished` / `.ownChannel` / `.subscriberReadOnly` / `.unknown(String)`。
- `not_found` 的两义不参与判断：资源是否存在由发起请求的路径和调用点决定，不由 `code` 推断。`presets_removed` 与普通 `not_found` 必须区分：前者是「旧接口已停用」，后者是资源缺失。
- `body`：`null`、字段缺失、`paragraphs` 为空数组三种情况一律归一化为 `nil`，走同一降级路径。
- `body.paragraphs[].segments[]`：`type` 为 `text` 取 `text`；为 `link` 且 `url` 可解析为合法 URL 时建链接片段，否则降级为纯文字；其他未知 `type` 按 `text` 处理，不丢内容。
- `summary`：`null`、字段缺失、空字符串三种情况一律归一化为 `nil`。

## 应用外壳与导航

- 三个标签：**日报**、**频道**、**我的**。每个标签各自的 `NavigationStack`。
- 标签栏与导航栏使用 iOS 26 系统能力（`TabView` / `NavigationStack` 的默认材质）呈现半透明玻璃效果，内容从其下方滚过；不手写毛玻璃材质。
- 导航栏品牌区：品牌图形 + 「Reach News」字标，居中；图形使用 `logo-mark-ink`（纸底）与 `logo-mark-paper`（深底）对应资源。
- 全局纸色外观，`.preferredColorScheme(.light)`。

## 日报流

日报页本身就是完整历史，没有独立的「全部」页。

- 元信息行：当天日期与星期、频道总数、已加载期数、右侧「最新优先」。
- 搜索框常驻顶部，按日报标题过滤已加载内容；输入即筛，无内容时显示空结果说明。
- 筛选按钮显示当前已应用维度数量；有筛选时按钮为深色激活态。
- 列表按 `createdAt` 倒序、按日期分组：今天、昨天使用相对词，更早使用「M月d日」。分组标题为小号大写风格标签加一条分隔线。
- 每行为紧凑行：标题（两行以内）、`summary`（非空时，一到两行截断）、频道标识点 + 频道名、时区时刻。不再显示分组数与素材数。
- `summary` 为 `nil` 或空字符串时不留空洞，行内直接进入元信息。
- 频道标识色由 `channelId` 稳定映射到 steel / moss / clay / plum 四色之一，保证同名频道跨屏一致。
- 滚动到底部自动加载下一页；加载中显示底部加载指示；到达边界显示无更多内容。
- 下拉刷新从接口重取最新一页并按 ID 合并。
- 新内容标注：进入页面与下拉刷新时按 `lastSeenAt` 拉 `/cursor?since=`；响应中出现的日报 ID 标记为「新」，并在行上给出标记。

## 筛选面板

从底部升起，覆盖在日报流之上。

- 时间：单选「全部时间 / 本周 / 本月 / 近三个月 / 自定义范围」；选择自定义范围时展示开始与结束日期字段。
- 频道：多选，列出全部已加载频道，每项带标识点。
- 页脚：「重置」与「显示 N 期」。`N` 为当前条件下已加载且符合筛选的期数，随选择实时更新。
- 应用筛选后，若所选范围的起点早于已加载边界，客户端继续请求后续页直到覆盖范围起点或到达数据边界，再呈现结果；不得只对已加载的 N 期做局部筛选。
- 已应用筛选以摘要行呈现，可逐个移除。

## 日报详情

- 头部：标题与 `M月d日 HH:mm`；**不显示分组数与素材数**（它们来自 `sections`，在读者端已不可见）。`summary` 非空时展示在标题下方、正文之前，为空时整块不渲染。
- **正文优先**：`body` 非空时渲染段落与行内链接。段落之间按正文间距排版，行高与行宽按长文阅读设置；不渲染成列表，不使用等宽字体。
- 正文 `segments[].text` 是 Markdown，按 CommonMark 渲染：小标题、列表、粗体、行内代码、引用块、代码块与链接都要正确呈现，界面上不出现字面的 `##`、`-`、`**`、``` 等标记。
- 用成熟 CommonMark 实现解析，不自研正则、不只处理部分语法；渲染范围严格限定 `body`。当前用 Foundation 自带的 `AttributedString(markdown:options:)`（`interpretedSyntax: .full`），不引入第三方依赖；块级样式（标题字号、列表标记、代码块底纹、引用竖线）由视图按 `presentationIntent` 施加。
- 渲染器覆盖：块级（标题 h1–h6、段落、无序/有序列表、引用块、围栏与缩进代码块、分隔线）与行内（粗体、斜体、行内代码、链接、删除线）。
- 代码块等宽显示并保留换行与缩进；不使用语法高亮。
- `title`、`summary`、`sections[].items[].title` 与 `.summary` 一律纯文本：即使含 Markdown 标记也原样显示，不解析。
- `link` 片段渲染为可点文本，点击用系统浏览器打开 `url`；`url` 缺失或非法的片段降级为纯文字，不产生死链。
- **正文缺失**：`body` 为 `nil` 或字段缺失时，标题与描述照常显示，正文区显示一句「本期无可读正文」的说明；不回退到分组渲染，页面不出现分组列表，也不报错。
- **读者端不渲染 `sections`**：详情页没有分组标题、条目卡与「本期采集」入口。`sections` 仍照常解析并保留在模型中（供后台核对与将来使用），但不进入这个界面。
- 页面结构固定为「标题 → 描述（非空时）→ 正文」，三段之外不追加其他区块。
- `body` 与 `sections` 是两件事：正文可只引用部分素材，`sections` 是本期全量条目。读者可读性由正文承担，不用 `sections` 补正文或反推正文内容。
- 运行状态不在此页以装置形式出现：`published` 只呈现日报本身。

## 追问胶囊

- 位于日报详情右下角，静止态为深色胶囊，含气泡图标与「追问」。
- 向下或向上滚动时收起为圆形图标，停止滚动后恢复为胶囊。
- 点击进入追问页。无障碍标签在两种形态下都读作「追问」。

## 追问

- 近单色工具风：与编辑风不同的背景、气泡与输入区 token 组。
- 导航栏：返回圆钮、两行标识（「本期日报」/「基于归档摘要」）、更多圆钮。
- 历史按游标分页加载，按日期插入日期分隔标签；用户回合右对齐深色气泡，助手回合左对齐浅色气泡。
- 输入栏：圆形加号按钮、圆角输入框、麦克风按钮。
- 发送后等待服务端同步返回并直接呈现回答；不显示「正在思考」、不逐字输出、不使用流式。回答到达前输入框保持可用状态与已发送消息的呈现即可，不额外造等待语汇。
- 请求失败时在会话内以可重试样式呈现失败的那一轮，不丢失已输入内容。
- 稿件中的「引用的素材 · N 条」内嵌卡按稿子留位，卡内标注「功能开发中」，并说明引用与归属数据待服务端支持。卡片不填入素材，也不表示这些素材是回答的依据。
- 「展开素材 X」依赖服务端的引用关系，标注为功能开发中。
- 不提供「看这期分组」快捷动作：读者端不再展示分组，该动作已移除。

## 删除频道

- 频道编辑页底部提供「删除频道」，使用警示色；只有 `owner == "creator"` 的频道入口存在。
- 点击后弹出二次确认，说明日报与素材会保留、但频道不再出现。
- 确认后调用 `DELETE /api/v1/channels/:id`。
- 成功（`200 { id, deleted: true }`）：从本地列表移除该频道并返回频道列表。
- `404`（别人的频道或已删除）：按已删除处理，同样移除本地条目并返回，不显示错误。
- `409`（有运行在跑）：提示该频道正在运行，等待结束后再删；不做任何本地删除。
- 其他错误：呈现归一化原因，保留当前页面。
- 订阅频道不渲染删除入口：服务端对订阅者的 `DELETE` 返回 `404`（按不存在处理，不泄露频道存在），客户端不把用户导向必然失败的路径。

## 时区

服务端新增只读 `GET /api/v1/settings`，返回 `{ timeZone }`；配置缺失或非法时回退 `Asia/Shanghai`。

- 启动取得时区后，客户端所有「时刻」展示与日期分组都按该时区解释，不再硬编码 `Asia/Shanghai`。
- 频道列表副行显示「按 {时区} 触发」，取服务端返回值；服务端配置变化后界面随之变化。
- 采集时间表编辑页的时间解释同样使用该时区。
- 请求失败或字段缺失时回退 `Asia/Shanghai`，不因时区接口失败阻断主流程。
- 不提供时区写入口（服务端也没有写接口）。

## 我的

页面内容自上而下：账号头部，然后是收藏、偏好、连接信息三个入口。

- 账号头部：左侧圆形头像，右侧三行文字，行尾右向箭头。
- 第一行为当前登录用户名。冷启动从 Keychain 恢复会话时 `AuthSession.userName` 为空，此时使用上次登录时记下的展示名；改名不影响凭证。
- 第二行为邮箱。后端当前没有该字段，统一显示缺省示例地址 `name@example.com`。
- 第三行为套餐标识，取 `free` / `pro` / `ultra` 之一；当前没有后端，恒显示 `ultra`。它是订阅套餐，不是「信任等级」，界面上不出现「信任等级」字样。
- 头像本轮固定显示缺省图形，不提供选图或上传入口；没有后端图片可用时不显示空白圆或破图。
- 行尾箭头保留参考图观感，但点击整行本轮不触发导航、请求或状态变化。
- 不新增用户资料请求：头部的用户名来自会话，邮箱与套餐是本地常量。
- 收藏日报列表：仅存于本机，不同步服务端，不改变服务端任何状态；可取消收藏并进入对应日报详情。
- 偏好：界面语言选择、Base URL 编辑。
- 连接信息：当前服务地址、更换凭证入口；更换凭证复用连接页的 `/health` + `/api/v1/channels` 双验证，通过后才覆盖 Keychain。
- 空收藏时只给空态标题与一句下一步说明，不展示任何服务端缓存内容。

## 频道列表

频道页是同一条滚动列表，按当前用户与频道的关系分三段呈现，顺序固定为「我的频道」「订阅的频道」「发现更多」。

- 头部大标题「频道」与副行「N 个频道 · 按 {时区} 触发」，`N` 为「我的 + 订阅的」总数，不含「发现更多」。
- 导航栏右侧常驻 `+` 新建入口；菜单只保留「新建频道」，不再有「从模板新建」。
- **我的频道**：`owner == "creator"` 的项。卡片形态与既有编辑风一致：标识点、名称、`follow` 显示「跟踪」徽标、`enabled` 开关、提示词两行截断、状态 chip、时间表描述、连接器名。
- 我的频道中 `published == false` 的项照常显示与编辑；界面不提供公开 / 取消公开入口（`published` 只有管理员能改）。
- **订阅的频道**：`owner == "subscriber" && subscribed` 的项。卡片只读：显示订阅色点、名称、创建者频道的时间表与连接器、日报最近时刻，并带「订阅」只读标记；不渲染 `enabled` 开关、编辑、立即运行与删除入口。
- **发现更多**：来自 `GET /api/v1/channels?discover=1`，只列出 `subscribed == false && owner != "creator"` 的项。默认折叠，展开后每项显示名称、方向摘要与「订阅」按钮，并显示可订阅数量。
- 「发现更多」数据在进入频道页时与默认列表并行加载，与刷新、下拉刷新一起重取；单次请求失败只让该段显示行内提示（折叠时也可见），不影响「我的」与「订阅的」两段。
- 三段均为空时（既没有频道也没有可订阅项）显示空态：「频道由管理员开通，或先订阅一个公开频道」。
- 开关切换即时生效：先本地翻转，调用 `PATCH /api/v1/channels/:id` 提交 `enabled`；失败则回滚并提示原因。只有我的频道有开关。
- 状态 chip 三色区分：运行中（`queued`/`collecting`/`writing`）用绿色系；`missed` 用中性灰；`failed` 用警示色。「未启用」在关闭状态显示为中性 chip。
- 时间表描述：把 `schedule` 渲染为「周一、三、五 08:00」「每天 07:30」「每周二 09:00」这类人读短语。
- 运行状态轮询只作用于屏幕内可见行：每 60 秒对可见频道逐个 `GET /api/v1/runs` 或 `GET /api/v1/channels/:id/runs` 取最近一条运行；页面不可见即停。订阅频道同样可轮询其运行状态（读取不区分身份）。
- 点击我的频道卡进入编辑页；点击订阅频道卡进入只读详情页。
- 频道标识色由 `channelId` 稳定映射；订阅频道优先使用 `subscriptionColor` 对应颜色，映射不上时回退本地色板，再回退按 `channelId` 的稳定色。

## 订阅频道

订阅频道的一切写入只发生在「订阅关系」上，频道本身对订阅者只读。

- 订阅：`POST /api/v1/channels/:id/subscribe`，请求体 `{ "color": "…" }`，`color` 取当前色板选中的颜色值（≤32 字符）。`201` 与 `200`（幂等重复）都视为成功：该频道从「发现更多」移到「订阅的频道」，不产生重复条目。
- 改订阅色：`PATCH /api/v1/channels/:id/subscribe`，请求体只含 `color`；成功后直接使用响应里的完整 channel DTO 刷新列表与详情，不重新拉整页。
- 取消订阅：`DELETE /api/v1/channels/:id/subscribe`，成功后该频道从「订阅的频道」移除，其日报立即从日报流、日报详情与频道筛选中消失；频道与已发布日报在服务端不删除。
- fork：`POST /api/v1/channels/:id/fork`，点击后弹出二次确认，说明「复制成我的频道，并取消当前订阅」；确认后按原名 fork（不额外填名），成功后新频道以 `owner == "creator"`、`published == false` 进入「我的频道」并进入编辑页，原订阅同时消失。
- 订阅色语义：客户端复用既有 12 色调色板。订阅时提交所选颜色的色值字符串；读取时把 `subscriptionColor` 与色板色值比对，命中即用该色，未命中或为空字符串时回退到本地色板（`ChannelColorStore`），再回退到按 `channelId` 的稳定色。服务端不维护色值枚举，客户端也不假设它返回的一定是合法色值。
- 订阅色为空字符串或 `null` 时按「未设置」处理，不渲染空色点，也不把空字符串显示在界面上。
- 编辑、保存、删除、立即运行在订阅频道上一律不渲染入口；服务端拒绝（`403 subscriber_read_only`）只作为兜底错误文案，不作为交互路径。

## 订阅频道详情

- 只读页面，进入后不提供导航栏「保存」。
- 展示：订阅色点与名称、频道方向（提示词）、口吻、采集时间表、连接器名、最近日报时刻。
- 时间表与连接器只读呈现。
- 动作放导航栏菜单（`ellipsis.circle`）：fork 成我的频道、取消订阅；取消订阅需二次确认，说明频道与历史日报不会删除。
- 改颜色是页面内的普通行（标题 + 色点 + 色名 + 行尾箭头），不是底部按钮。
- 页面不使用底部通栏按钮。
- 顶部在动作失败时给出行内提示，呈现归一化原因，保留当前页面。

## 错误映射（订阅相关）

- `403 not_published`：「该频道尚未公开」。
- `409 own_channel`：「这是你自己的频道」。
- `403 subscriber_read_only`：「订阅频道只读，可 fork 后修改」。
- `404 presets_removed`：「旧接口已停用」。
- `400 invalid_input`（颜色超长或缺字段）：「颜色最多 32 个字符」。
- 以上均走统一错误归一化与本地化键，视图内不散落 switch。

## 新建频道

- 频道页 `+` 菜单只有「新建频道」一项，进入新建页；不再有「从模板新建」。
- 字段：名称（必填）、频道方向（必填）、口吻、采集时间表、连接器（多选，至少一个）、标识色。
- 连接器为空时在提交前提示「请至少选择一个连接器」，不提交会必然 `missed` 的频道。
- 提交调用 `POST /api/v1/channels`，请求体 `{ name, prompt, tone, schedule, connectorIds }`。
- 成功后新频道作为 `owner == "creator"` 进入「我的频道」，并按所选标识色写入本地色板。
- 创建流程不请求任何预设接口；`GET /api/v1/presets` 与 `/presets/:id/instantiate` 已下线，客户端不得再调用。

## 频道编辑

- 整页一次保存：导航栏「取消」「编辑频道」「保存」。只有 `owner == "creator"` 的频道进入此页。
- 字段：名称（单行）、提示词（多行）、口吻（单行）、采集时间表（星期多选 + 时间点 pill 增删）、连接器（只读列表）。
- 字段只用标签 + 控件，不写解释性小字。
- 保存调用 `PATCH /api/v1/channels/:id`，只提交被改动的字段。
- 服务端返回 `409 busy` 时：顶部出现警示样式提示「频道正在运行，暂时无法保存。结束后可修改，已填写的内容不会丢失。」，表单内容全部保留，用户可稍后重试。
- 其他错误按错误归一化呈现原因，同样保留输入。

## 运行状态

客户端按三分法呈现运行：

- `queued` / `collecting` / `writing`：轻量进行中指示，无可用动作。
- `published`：不显示运行装置，只呈现日报。「重新生成」仅在存在日报时可出现（ADR 0004 允许的形式）。
- `missed`：中性色，文案「本次未产出日报」。`no-material` 与 `queue-timeout` 都不提供重试。
- `failed`：警示色，文案「运行失败，素材已保留」。
- `cancelled`：服务端没有路径会进入该状态，客户端不实现取消按钮。

## 空态与错误

- 无频道且无可订阅项：说明频道由管理员开通，或先订阅一个公开频道；不提供无效的「新建」入口以外的假入口。
- 频道 `connectorIDs` 为空且 `enabled`：提示「未配置连接器，运行将不会产出日报」。订阅频道不显示该提示（连接器由创建者决定）。
- 断网：直接提示「当前无网络」，不展示任何缓存内容；页面为空态而非降级内容。
- 未授权（401）：提示凭证失效并引导回到连接页重新输入。
- 请求失败：显示错误原因与重试入口，保留页面上已有的可交互状态。

## 鉴权与连接

后端以账号密码换取短期会话凭证；旧的长期 Bearer Token 已全部失效。

- 首次启动无会话进入登录页：Base URL 预填 `reachapi.niuma.art` 且可编辑；填写账号与密码。
- 登录调用 `POST /api/v1/login`，请求体为 JSON `{username, password}`。
- 成功后保存 `token` 与 `expiresAt` 到 Keychain 与本机偏好，进入主界面。
- 失败时给出归一化原因且**不写入任何凭证**；凭据错误不区分「用户不存在」与「密码错误」。
- 密码只在提交时使用，成功后立即从内存清空；不落盘、不写日志。
- `429 too_many_attempts`：显示锁定提示并禁用提交按钮，**不自动重试**，冷却结束前不放行；冷却期内的提交直接拦在本地。
- 会话 7 天有效；启动时若已过期则丢弃并回登录页。
- 任何请求收到 401：清本地凭证并回登录页，不自动重试。
- 退出登录调用 `POST /api/v1/logout`；无论返回值如何都立即清本地凭证。
- 所有 `/api/v1` 请求带 `Authorization: Bearer <会话凭证>`；不访问 `/admin/*` 与 `/admin/api/*`。
- 「我的」页展示当前地址、凭证是否已保存、到期时间，并提供退出登录。

## 分页

- 参数 `?cursor=<offset>&limit=<n>`；`limit` 固定使用 20 或显式正整数，永不为 0、负数或超过 100。
- 客户端从不传负 `cursor`，也不把负值持久化。
- 深分页不稳定因此只用于向后滚动；「是否有新内容」与去重一律靠 ID 集合与 `lastSeenAt`，不靠偏移。

## 轮询

- 无 SSE / WebSocket / 推送可用，全部靠轮询。
- 进入日报页拉一次 `GET /api/v1/cursor?since=<lastSeenAt>`；停留期间每 60 秒一次；下拉刷新额外触发；离开页面即停。
- 请求总是带 `since`；无历史基线时以 1970 年作为起点全量拉取。
- 推进 `lastSeenAt` 时取响应中最大的 `created_at`，不用本地当前时间。
- 响应中 `channels` 视为配置被改动，触发频道列表刷新。

## 持久化

- 不缓存日报与素材内容。两个 Store 分开：`AppSettings.lastSeenAt`（轮询基线，几十字节元数据）与内容 Store 严格分开命名与存放。
- 收藏仅存本机、不同步服务端、不改变服务端状态。
- 界面语言与 Base URL 存本地偏好。

## 界面文案与动作位置

遵循苹果的交互理念，界面默认只给「标题 + 交互组件」。

- 不为标题、字段、按钮配解释性小字；用户能从标签与控件本身理解的部分一律不加辅助文案。
- 表单字段用标签加控件即可，不写「这个字段决定什么」「如何填写」之类的引导语。
- 仅以下情况保留文字：不可逆操作前的二次确认说明；服务端拒绝与校验失败的错误原因；空态需要用户知道下一步做什么。
- 不使用底部通栏大按钮作为页面主操作。主操作放导航栏（如「保存」「完成」），或作为列表行、行尾箭头、开关、分段控件等 iOS 惯用控件。
- 破坏性操作走导航栏菜单或行内入口加二次确认。
- 整宽按钮仅用于单一任务的一次性确认（如登录页提交）。

## 设计 token

两套 token 并存，按界面归属选用，视图内不写字面色值：

- 编辑风（日报、频道、我的）：`canvas` #FBFAF7、`paper` #F1EFE9、`surface` #FFFFFF、`ink` #14140F、`ink2` #53514A、`ink3` #8B877E、`line` 黑 10%、`chip` #F2F0EA。
- 追问风（追问页）：`askBackground` #F6F5F2、`askSurface` #FFFFFF、`askBubble` #EFEDE8、`askUser` #121211。
- 状态：`running` #EAF0EC / 前景 #3D6B5C、`missed` #EFEDE7、`failed` #FAF0EC / 前景 #A5452A。
- 频道标识：12 色调色板（azure #2F6F9E、emerald #2E7D5B、ember #B05A2A、magenta #8C3B63、violet #6A4FA0、amber #B08615、teal #1F7A76、brick #9C2F2F、olive #4A5D23、indigo #2E4E8F、walnut #7A5C3E、graphite #4A4A55）。同一色板同时承载订阅色：订阅时提交色值字符串，读取时比对，未命中按「未设置」回退。
- 圆角：8 / 12 / 16。数字使用压缩体（Barlow Condensed 族或系统 condensed 宽度）。

## 本地化

- 界面文案全部走本地化键，`zh-Hans` 全量覆盖新界面，`en.lproj` 与中文键集完全对齐。
- 跟随系统语言；缺失译文回落中文。
- 术语使用 `GLOSSARY.md` 的词表：频道、日报、分组、条目、素材、运行、采集时间表、口吻、连接器、错过、失败、追问、收藏、偏好。

## 功能开发中约定

稿件中出现、但当前服务端未提供数据支撑的位置，先按稿子做出界面，并在该位置显示「功能开发中」，同时不展示伪造数据：

- 追问页的引用素材卡与「展开素材 X」快捷动作。

这些位置不承担任何验收结论，也不得填入替代数据来掩盖服务端缺口。频道新建入口的保存动作在 `GET /api/v1/connectors` 可用后已落地，不再属于本节。

## 测试策略

- 单元测试覆盖：DTO 解码（含 `/cursor` snake_case 与整数 `enabled`、频道五个订阅字段、空字符串 `subscriptionColor`）、时间解析与时区展示、`missedReason`/`error.code` 的未知值保留、四个订阅错误码归一化、分页参数构造拒绝负值与越界、`lastSeenAt` 取最大 `created_at`、筛选与去重逻辑、频道可写性三判定（`canEdit`/`canSubscribe`/`canUnsubscribe`）、订阅与取消订阅与改色与 fork 的请求方法与路径、频道编辑只提交改动字段、`409 busy` 不丢输入。
- 本轮的正文与摘要另需覆盖：`body` 的三种状态（有正文 / `null` / 字段缺失）、`paragraphs` 为空数组、`link` 缺 `url` 时降级为纯文字、未知 segment `type` 按纯文字处理、`summary` 为 `null` 与空字符串、以及「无论是否有正文都不渲染 `sections`」。
- Markdown 渲染另需覆盖：`## 小标题`、无序列表、有序列表、`**粗体**`、`*斜体*`、行内代码、引用块、围栏代码块与链接，各自解析为对应视图而非字面标记；覆盖一期里同时出现多种语法；并确认 `title` / `summary` / `sections` 中的同种标记不被解析。
- 样本取自 `Fixtures/*.json`，必须覆盖：`lastBriefAt: null`、`connectorIds: []`、`owner: "subscriber"` 的订阅项、`subscriptionColor: ""`、`published: false` 的自建频道、`missed` + `no-material`、`failed`、多分组、条目引用多条素材；另需覆盖带 `body` 的日报、`body: null` 的日报、`summary: null` 的日报。
- UI 测试以可访问性标识驱动，覆盖日报流的搜索与筛选、频道卡开关、订阅卡无编辑入口、订阅按钮把项从「发现更多」移入「订阅的频道」、编辑页 `409` 提示；UI 测试不打真实网络，使用可注入的固定响应。
- 构建与测试证据来自 GitHub Actions 的 iOS 任务；Android 任务只需 `assembleDebug` 继续通过。

## 非支持能力

客户端不得假装具备以下能力，界面相应位置保持缺失或明确不可用：

- 公开或取消公开频道：`published` 只有管理员能切换，`POST /channels` 传入 `published: true` 会被忽略；客户端不提供公开开关。
- 订阅者修改频道、触发运行或删除频道：服务端分别返回 `403 subscriber_read_only` 与 `404`，客户端不渲染这些入口。
- 追问接入 LLM（`answer` 是确定性拼接）。
- 为 `missed` 运行提供重新生成（ADR 0004）。
- 枚举或选择连接器（`/admin/api/connectors` 需管理员鉴权）。
- 取消运行（服务端无路径进入 `cancelled`）。
- 依赖 `PUT` 等未实现方法的方法错误区分（服务端回 404）。
- 在读者端展示 `sections` 分组、条目卡或「本期采集」入口；`sections` 不进入这个界面。
- 把 `sections` 当作正文的脚注或字幕，或用它反推正文应当写什么。
- 对 `body` 以外的字段做 Markdown 解析：`title`、`summary`、`sections` 的标题与摘要一律纯文本。
- 在正文里渲染 HTML：正文只按 CommonMark 处理，不引入 HTML 渲染。
- 读取频道的 `title` / `description` / `displayTitle`（服务端已移除）。

## 范围约束

- 本轮只交付 iOS。
- `android/**` 不做任何改动，仅要求 `assembleDebug` 继续通过。
