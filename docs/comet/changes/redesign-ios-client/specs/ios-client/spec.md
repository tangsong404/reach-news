# iOS 客户端完整规格

本 capability 描述重构后 iOS 客户端在归档时应具备的完整行为。数据来自 `reachapi.niuma.art` 的 `/api/v1`，界面依据 `design/mockups/v2.html`，行为约束来自 `docs/client-contract.md`、`docs/adr/` 与 `GLOSSARY.md`。

## 领域模型

客户端在与服务端边界处一次性完成归一化，内部只使用本节的类型与命名。术语严格遵循 `GLOSSARY.md`：`items` 在日报 payload 里是**条目**（`Entry`），`itemId` 指向的是**素材**（`Material`），两者不可混称。

- `Channel`：`id`、`name`、`prompt`、`tone`、`schedule: Schedule`、`enabled: Bool`、`connectorIDs: [String]`、`lastBriefAt: Date?`、`kind: ChannelKind`、`createdAt`、`updatedAt`。
- `ChannelKind`：`.channel` / `.follow` / `.preset`。`follow` 显示「跟踪」徽标；`preset` 是管理员模板频道且会参与调度，普通用户列表不展示。
- `Schedule`：周一到周日各可配零到多个 `HH:MM`；未配置的星期视为无触发。所有时刻按 `Asia/Shanghai` 解释。
- `Brief`：`id`、`channelID`、`title`、`sections: [BriefSection]`、`memorySummary`、`createdAt: Date`。
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
- `error.code` 归一化为 `.unauthorized` / `.tooManyAttempts` / `.notFound` / `.invalidInput` / `.busy` / `.badRequest` / `.internalError` / `.unknown(String)`。
- `not_found` 的两义不参与判断：资源是否存在由发起请求的路径和调用点决定，不由 `code` 推断。

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
- 每行为紧凑行：标题（两行以内）、频道标识点 + 频道名、`Asia/Shanghai` 时刻、分组数、素材数。素材数取自该期全部条目的 `materialIDs` 去重计数。
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

- 头部：标题、`M月d日 HH:mm`、分组数、素材数。
- 每个分组以吸顶标题呈现：分组名 + 「N 条」，吸顶时带背景模糊。
- 每个条目为白底卡片：标题、摘要、素材数、展开箭头。
- 展开后内联显示该条目的素材行：字母方块（取自来源域名首字母两字以内）、标题单行截断、域名、外开箭头。
- 素材行点击用系统浏览器打开 `url`。`content` 字段在客户端任何位置都不渲染。
- 素材文本按需调用 `GET /api/v1/briefs/:id/items/:itemId` 获取；列表页不带正文，因此进入详情前也无需预取。
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
- 快捷动作中「看这期分组」可跳转到本期分组；「展开素材 X」依赖服务端的引用关系，标注为功能开发中。

## 删除频道

- 频道编辑页底部提供「删除频道」，使用警示色。
- 点击后弹出二次确认，说明日报与素材会保留、但频道不再出现。
- 确认后调用 `DELETE /api/v1/channels/:id`。
- 成功（`200 { id, deleted: true }`）：从本地列表移除该频道并返回频道列表。
- `404`（别人的频道或已删除）：按已删除处理，同样移除本地条目并返回，不显示错误。
- `409`（有运行在跑）：提示该频道正在运行，等待结束后再删；不做任何本地删除。
- 其他错误：呈现归一化原因，保留当前页面。

## 时区

服务端新增只读 `GET /api/v1/settings`，返回 `{ timeZone }`；配置缺失或非法时回退 `Asia/Shanghai`。

- 启动取得时区后，客户端所有「时刻」展示与日期分组都按该时区解释，不再硬编码 `Asia/Shanghai`。
- 频道列表副行显示「按 {时区} 触发」，取服务端返回值；服务端配置变化后界面随之变化。
- 采集时间表编辑页的说明同样使用该时区。
- 请求失败或字段缺失时回退 `Asia/Shanghai`，不因时区接口失败阻断主流程。
- 不提供时区写入口（服务端也没有写接口）。

## 我的

- 收藏日报列表：仅存于本机，不同步服务端，不改变服务端任何状态；可取消收藏并进入对应日报详情。
- 偏好：界面语言选择、Base URL 编辑。
- 连接信息：当前服务地址、更换凭证入口；更换凭证复用连接页的 `/health` + `/api/v1/channels` 双验证，通过后才覆盖 Keychain。
- 空收藏时给出说明，不展示任何服务端缓存内容。

## 频道列表

- 头部大标题「频道」与副行「N 个频道 · 按 Asia/Shanghai 触发」。
- 导航栏右侧常驻 `+` 新建入口。ADR 0004 决定该入口可见，但在 `/api/v1` 提供连接器枚举前不落地保存动作；点击时说明功能开发中，不提供会建出跑不起来频道的路径。
- 频道卡：标识点、名称、`follow` 显示「跟踪」徽标、`enabled` 开关、提示词两行截断、状态 chip、时间表描述。
- 开关切换即时生效：先本地翻转，调用 `PATCH /api/v1/channels/:id` 提交 `enabled`；失败则回滚并提示原因。
- 状态 chip 三色区分：运行中（`queued`/`collecting`/`writing`）用绿色系；`missed` 用中性灰；`failed` 用警示色。
- 「未启用」在关闭状态显示为中性 chip。
- 时间表描述：把 `schedule` 渲染为「周一、三、五 08:00」「每天 07:30」「每周二 09:00」这类人读短语。
- 运行状态轮询只作用于屏幕内可见行：每 60 秒对可见频道逐个 `GET /api/v1/runs` 或 `GET /api/v1/channels/:id/runs` 取最近一条运行；页面不可见即停。
- 点击频道卡进入编辑页。

## 频道编辑

- 整页一次保存：导航栏「取消」「编辑频道」「保存」。
- 字段：名称（单行）、提示词（多行）、口吻（单行）、采集时间表（星期多选 + 时间点 pill 增删）、连接器（只读列表 + 说明「手机端暂不支持调整连接器，请在管理后台修改」）。
- 提示词下方给出说明「决定这个频道产出什么，写作者按它取舍素材」；时间表下方给出说明「统一按 Asia/Shanghai 解释；同一分钟只入队一次」。
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

- 无频道：说明频道由管理员开通；不提供无效的「新建」入口。
- 频道 `connectorIDs` 为空且 `enabled`：提示「未配置连接器，运行将不会产出日报」。
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

## 设计 token

两套 token 并存，按界面归属选用，视图内不写字面色值：

- 编辑风（日报、频道、我的）：`canvas` #FBFAF7、`paper` #F1EFE9、`surface` #FFFFFF、`ink` #14140F、`ink2` #53514A、`ink3` #8B877E、`line` 黑 10%、`chip` #F2F0EA。
- 追问风（追问页）：`askBackground` #F6F5F2、`askSurface` #FFFFFF、`askBubble` #EFEDE8、`askUser` #121211。
- 状态：`running` #EAF0EC / 前景 #3D6B5C、`missed` #EFEDE7、`failed` #FAF0EC / 前景 #A5452A。
- 频道标识：steel #4E6E8E、moss #3D6B5C、clay #A9714B、plum #7A5A78。
- 圆角：8 / 12 / 16。数字使用压缩体（Barlow Condensed 族或系统 condensed 宽度）。

## 本地化

- 界面文案全部走本地化键，`zh-Hans` 全量覆盖新界面，`en.lproj` 与中文键集完全对齐。
- 跟随系统语言；缺失译文回落中文。
- 术语使用 `GLOSSARY.md` 的词表：频道、日报、分组、条目、素材、运行、采集时间表、口吻、连接器、错过、失败、追问、收藏、偏好。

## 功能开发中约定

稿件中出现、但当前服务端未提供数据支撑的位置，先按稿子做出界面，并在该位置显示「功能开发中」，同时不展示伪造数据：

- 追问页的引用素材卡与「展开素材 X」快捷动作。
- 频道 `+` 新建入口的保存动作。

这些位置不承担任何验收结论，也不得填入替代数据来掩盖服务端缺口。

## 测试策略

- 单元测试覆盖：DTO 解码（含 `/cursor` snake_case 与整数 `enabled`）、时间解析与 `Asia/Shanghai` 展示、`missedReason`/`error.code` 的未知值保留、分页参数构造拒绝负值与越界、`lastSeenAt` 取最大 `created_at`、筛选与去重逻辑、频道编辑只提交改动字段、`409 busy` 不丢输入。
- 样本取自 `Fixtures/*.json`，必须覆盖：`lastBriefAt: null`、`connectorIds: []`、`missed` + `no-material`、`failed`、多分组、条目引用多条素材。
- UI 测试以可访问性标识驱动，覆盖日报流的搜索与筛选、频道卡开关、编辑页 `409` 提示、追问胶囊两种形态；UI 测试不打真实网络，使用可注入的固定响应。
- 构建与测试证据来自 GitHub Actions 的 iOS 任务；Android 任务只需 `assembleDebug` 继续通过。

## 非支持能力

客户端不得假装具备以下能力，界面相应位置保持缺失或明确不可用：

- 手机端创建或删除频道（无 `POST /channels`、无 `DELETE /channels/:id`）。
- 追问接入 LLM（`answer` 是确定性拼接）。
- 为 `missed` 运行提供重新生成（ADR 0004）。
- 枚举或选择连接器（`/admin/api/connectors` 需管理员鉴权）。
- 取消运行（服务端无路径进入 `cancelled`）。
- 依赖 `PUT` 等未实现方法的方法错误区分（服务端回 404）。

## 范围约束

- 本轮只交付 iOS。
- `android/**` 不做任何改动，仅要求 `assembleDebug` 继续通过。
