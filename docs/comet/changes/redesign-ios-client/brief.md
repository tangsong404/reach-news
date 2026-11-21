# 目标

把 Reach News 的 iOS 客户端从「内置样例 JSON 的离线原型」重构为真实 API 驱动的产品级客户端：

- 界面按 `design/mockups/v2.html` 实现，包括两套视觉语言（编辑风日报/频道 + 近单色追问）、液态玻璃导航、日期分组信息流、筛选面板、频道编辑与追问胶囊。
- 数据全部走 `reachapi.niuma.art` 的真实 `/api/v1` 接口，按 `docs/client-contract.md` 完成归一化、状态映射、分页、轮询、鉴权与错误处理。
- 遵守 `docs/adr/` 的四条决策，尤其是「只做 iOS」「不做离线内容缓存」「不包装服务端尚未支持的能力」。

交付物是一个装上就能用真实 token 连接、读真实频道与日报的 iOS app，以及支撑它的单元测试和可复现的 CI 构建证据。

# 范围

本轮改动集中在 `ReachNews/`（iOS 源码、资源、测试）、`project.yml` 与 `.github/workflows/build.yml`。`android/` 不改代码，只需 `assembleDebug` 继续通过。

## 目录结构

新建：

- `ReachNews/App/RootTabView.swift` — 三个标签（日报 / 频道 / 我的）与各自的 `NavigationStack`；液态玻璃标签栏与导航栏使用系统能力。
- `ReachNews/App/AppEnvironment.swift` — 依赖装配：`APIClient`、各 Store、`AppSettings`，供 `@Environment` 注入与 Preview 覆写。
- `ReachNews/Design/Tokens.swift` — 语义 token：编辑风组（`canvas`/`paper`/`surface`/`ink`/`ink2`/`ink3`/`line`）与追问风组（`askBackground`/`askSurface`/`askBubble`/`askUser`），状态色（`running`/`missed`/`failed`），频道标识色（steel/moss/clay/plum），圆角与间距刻度，压缩体数字字体。
- `ReachNews/Design/Components.swift` — 复用件：`ChannelDot`、`MetaLine`/`DotSeparator`、`DayRule`、`StatusChip`、`SectionStickyHeader`、`NavCircleButton`、`PrimaryButton`、`EmptyStateView`、`LoadMoreIndicator`。
- `ReachNews/Domain/Models.swift` — `Channel`、`Brief`、`BriefSection`、`Entry`、`Material`、`Run`、`AskTurn`、`CursorPayload`。
- `ReachNews/Domain/Enums.swift` — `RunState`、`MissedReason`（含 `.unknown(String)`）、`APIErrorCode`（含 `.unknown`）、`ChannelKind`、`Schedule`（周一到周日 + `HH:MM`，Asia/Shanghai 解释）与展示用格式化。
- `ReachNews/Data/APIClient.swift` — `URLSession` 封装：Bearer 注入、超时、`APIError` 归一化、`GET/POST/PATCH`、分页参数构造（拒绝负值）。
- `ReachNews/Data/DTO/` — `ChannelDTO`、`BriefDTO`、`MaterialDTO`、`RunDTO`、`AskDTO`、`CursorDTO`、`ErrorEnvelope`；`snake_case` 转换、`enabled` 整数转 `Bool`、ISO8601 毫秒时间戳解析、`missedReason` 与 `code` 枚举化。
- `ReachNews/Data/Keychain.swift` — Bearer token 存取（`kSecClassGenericPassword`），失败时返回明确错误而非静默。
- `ReachNews/Data/AppSettings.swift` — 用户偏好（base URL、语言、`lastSeenAt`）；`lastSeenAt` 独立命名与独立存储，不承载任何内容缓存。
- `ReachNews/State/SessionStore.swift` — 连接状态、`/health` + `/api/v1/channels` 双验证、写入或覆盖凭证。
- `ReachNews/State/BriefFeedStore.swift` — 日报流：分页加载、按 `channelId/createdAt` 去重、搜索与筛选（时间预设 + 自定义范围 + 频道多选）、加载到筛选范围起点、下拉刷新、新内容标注。
- `ReachNews/State/ChannelStore.swift` — 频道列表、`enabled` 乐观切换与失败回滚、可见行运行状态轮询、`PATCH` 保存与 `409 busy` 处理。
- `ReachNews/State/AskStore.swift` — 单期日报的追问历史（分页）与发送，不做流式与「思考中」。
- `ReachNews/State/SavedStore.swift` — 本机收藏集合（仅本地，不同步服务端）。
- `ReachNews/Features/Briefs/` — `BriefFeedView`、`BriefRow`、`FeedFilterSheet`、`DateRangeFields`、`FeedSearchBar`。
- `ReachNews/Features/BriefDetail/` — `BriefDetailView`、`EntryCard`、`MaterialRow`（`content` 永不渲染）、`AskPill`（展开/收起两态）。
- `ReachNews/Features/Ask/` — `AskView`、`AskBubble`、`AskComposer`。
- `ReachNews/Features/Channels/` — `ChannelListView`、`ChannelCard`、`ChannelEditView`、`ScheduleEditor`（星期多选 + 时间点增删）。
- `ReachNews/Features/Me/` — `MeView`、`SavedBriefsView`、`PreferencesView`、`ConnectionInfoView`（当前服务地址与更换凭证）。
- `ReachNews/Features/Connection/` — `ConnectionView`（首次启动无 token 时进入）。
- `ReachNews/Resources/Assets.xcassets/` — `AppIcon`（取自 `design/brand/icon-light.png`）与导航栏品牌图形（`logo-mark-ink.png` / `logo-mark-paper.png`）。
- `ReachNews/Resources/en.lproj/Localizable.strings` — 新增英文，键集与中文完全对齐。
- `ReachNewsTests/` — `DTODecodingTests`、`NormalizationTests`、`PaginationTests`、`PollingBaselineTests`、`FilterTests`、`ChannelEditTests`、`FixtureReachabilityTests`。

修改：

- `ReachNews/ReachNewsApp.swift` — 装配新环境、连接态路由、locale 与 `preferredColorScheme(.light)`（稿子只有纸色）。
- `ReachNews/Resources/zh-Hans.lproj/Localizable.strings` — 按新界面重写键集，术语遵循 `GLOSSARY.md`。
- `project.yml` — 资源改为 `Assets.xcassets` + 两个 `.lproj`，移除 `stories.json` 与不存在的 `UIAppFonts` 字体引用。
- `.github/workflows/build.yml` — iOS 任务新增真实的测试执行（`xcodebuild test`，模拟器目标），去掉手工拷贝 `stories.json` 的步骤；Android 任务保持 `assembleDebug`。
- `README.md` — 改为真实 API 客户端的说明与构建方式。
- `ReachNewsUITests/ReachNewsUITests.swift` — 覆写为针对新信息流、筛选、频道编辑的可访问性标识断言，不在 UI 测试里打真实网络。

删除：

- `ReachNews/Models.swift`、`DesignSystem.swift`、`RootView.swift`、`DetailViews.swift`、`CollectionViews.swift`、`WorkspaceViews.swift` — 均绑定于样例数据与旧版政治光谱信息架构。
- `ReachNews/Resources/stories.json` — 样例数据不再随包发布。
- `ReachNewsTests/NewsStoreTests.swift` — 被新的测试文件替代。

明确不建：

- 不做 Android 任何改动（`android/**` 保持字节不变）。
- 不建离线内容缓存、收藏同步、推送、SSE/WebSocket。
- 不建频道创建与频道删除的保存动作（ADR 0004）。
- 不为 `missed` 运行提供「重新生成」（ADR 0004）。

## Source coverage

覆盖边界：用户明确给出的五个需求来源的全文，以及它们为正确理解所必需的必要依赖。

- 界面行为边界 = `design/mockups/v2.html` 全部 8 屏、token 区与说明文字。
- 客户端行为边界 = `docs/client-contract.md` 全文。
- 协议边界 = `/var/lib/dsh/reach-news/API.md` 全文（含「已知缺口」）。
- 约束边界 = `docs/adr/0001`–`0004` 全文、`GLOSSARY.md` 全文。

### `design/mockups/v2.html`

| 来源条目与位置 | 读取状态 | 需要保留的内容 | Spec 位置 | 验收 ID | 覆盖状态 | 理由或替代关系 |
| --- | --- | --- | --- | --- | --- | --- |
| S1 token 区「底色与层次」「文字」「状态」「频道标识」「字体」 | complete | 两套语义 token、三种状态色、四种频道标识色、压缩体数字 | specs/ios-client/spec.md#设计 token | 待分配 | covered | 当前有效需求 |
| S2 `.topglass`/`.navbar`/`.tabbar` 与稿头「导航栏与标签栏改为 iOS 26 原生液态玻璃」 | complete | 半透明玻璃、内容从下方滚过、三个标签（日报/频道/我的） | #应用外壳与导航 | 待分配 | covered | 当前有效需求 |
| S3 屏 01 `.metalines`「11月20日 星期四 · 4 个频道 · 共 47 期 · 最新优先」 | complete | 元信息行三计数 + 排序标识 | #日报流 | 待分配 | covered | 当前有效需求 |
| S4 屏 01 `.searchrow` 搜索框 + 筛选按钮 | complete | 搜索常驻、筛选入口；筛选激活时显示已应用数量 | #日报流 | 待分配 | covered | 当前有效需求 |
| S5 屏 01 `.dayrule`「今天」「昨天」「11月18日」 | complete | 日期分组倒序，今天/昨天用相对词，更早用日期 | #日报流 | 待分配 | covered | 当前有效需求 |
| S6 屏 01 `.row` 字段（标题、频道点+名、时间、分组数、素材数） | complete | 紧凑行承载的六类信息 | #日报流 | 待分配 | covered | 当前有效需求 |
| S7 屏 02 筛选面板全部内容（时间单选四项、自定义范围、频道多选、重置、显示 N 期） | complete | 单选时间 + 多选频道 + 页脚动作 | #筛选面板 | 待分配 | covered | 当前有效需求 |
| S8 屏 02 说明「选具体范围时客户端会持续加载到该范围起点为止再显示」 | complete | 筛选须加载到范围起点，不得只筛已加载部分 | #筛选面板 | 待分配 | covered | 当前有效需求 |
| S9 屏 03 `.detail-head`（标题、日期时间、分组数、素材数） | complete | 详情头部信息 | #日报详情 | 待分配 | covered | 当前有效需求 |
| S10 屏 03 `.section-sticky` 吸顶分组标题 + 条数 | complete | 分组吸顶与模糊 | #日报详情 | 待分配 | covered | 当前有效需求 |
| S11 屏 03 `.entry`（标题、摘要、素材数、展开/收起） | complete | 条目卡与内联展开 | #日报详情 | 待分配 | covered | 当前有效需求 |
| S12 屏 03 `.mat`（字母方块、标题、域名、外开箭头） | complete | 素材行只显示标题与域名并可外开 | #日报详情 | 待分配 | covered | 当前有效需求 |
| S13 屏 03 `.ask-pill` 与屏 07/08 两态说明 | complete | 浮动胶囊：静止展开「追问」，滚动收起为圆形 | #追问胶囊 | 待分配 | covered | 当前有效需求 |
| S14 屏 04 `.chan-card`（点、名称、跟踪徽标、开关、提示词、状态 chip、时间表） | complete | 频道卡全部元素 | #频道列表 | 待分配 | covered | 当前有效需求 |
| S15 屏 04 说明「`enabled` 行上直接切换、即时生效（失败则回滚）」 | complete | 乐观切换 + 失败回滚 | #频道列表 | 待分配 | covered | 当前有效需求 |
| S16 屏 04 说明「运行状态用中性 chip；『错过』是灰色而非错误色」，`.chip.run`/`.chip.warn` | complete | 运行中/错过/失败三色区分 | #频道列表 | 待分配 | covered | 当前有效需求 |
| S17 屏 05 编辑页字段（名称、提示词、口吻、采集时间表、只读连接器）与说明「连接器只读并注明需在管理后台调整」 | complete | 可编辑字段与连接器只读 | #频道编辑 | 待分配 | covered | 当前有效需求 |
| S18 屏 05 `.notice` 与说明「运行中 409 在顶部提示，已填内容全部保留」 | complete | `409 busy` 顶部提示且不清空输入 | #频道编辑 | 待分配 | covered | 当前有效需求 |
| S19 屏 06 追问页（导航标识、日期分隔、bot/me 气泡、输入栏 `+`/输入框/麦克风） | complete | 近单色工具风与底部三件套 | #追问 | 待分配 | covered | 当前有效需求 |
| S20 屏 06 说明「回答到达前不显示『正在思考』或逐字输出」 | complete | 非流式、无打字机 | #追问 | 待分配 | covered | 当前有效需求 |
| S21 屏 04 导航栏 `+` 新建入口常驻 | complete | 新建入口可见，但保存动作等端点 | #频道列表 | 待分配 | covered | 与 D5 一致：入口保留、保存标开发中 |
| S23 屏 06 `.inbubble-card`「引用的素材 · 3 条」内嵌卡 | complete | 卡片结构（表头、序号、标题、域名） | #追问 | 待分配 | covered | Q3：留位并标「功能开发中」，不填数据 |
| S24 屏 06 `.ask-actions`「展开素材 C」「看这期分组」 | complete | 两个快捷动作 | #追问 | 待分配 | covered | Q3：「看这期分组」实现，「展开素材 X」标开发中 |
| S25 屏 01/04 标签栏第三项「我的」 | complete | 第三个标签存在 | #我的 | 待分配 | covered | Q2：收藏 + 偏好 + 连接信息 |
| S22 页脚「本稿不含：设置页、连接页、空态与错误态」与「与 v1 的差别」 | complete | 稿子范围外页面由其他来源定义，不据此自造 | — | — | background | 范围说明，非需实现条目 |

### `docs/client-contract.md`

| 来源条目与位置 | 读取状态 | 需要保留的内容 | Spec 位置 | 验收 ID | 覆盖状态 | 理由或替代关系 |
| --- | --- | --- | --- | --- | --- | --- |
| C1 「术语」段：`sections[].items[]` 是条目、`itemId` 指向素材、不可混称 | complete | 领域命名以 GLOSSARY 为准 | #领域模型 | 待分配 | covered | 当前有效需求 |
| C2 「字段归一化」表五行（snake_case、`enabled`、时间戳、`missedReason`、`error.code`） | complete | 边界一次性归一化，UI 只见 camelCase/`Date`/枚举 | #字段归一化 | 待分配 | covered | 当前有效需求 |
| C3 「`not_found` 有两义…只能靠请求路径区分」 | complete | 不以 code 推断资源不存在 | #错误处理 | 待分配 | covered | 当前有效需求 |
| C4 「状态三分法」表与 `cancelled` 行 | complete | 四态呈现与可用动作；不实现取消按钮 | #运行状态 | 待分配 | covered | 当前有效需求 |
| C5 「`missed` 不是失败」段（两种原因、都不提供重试） | complete | missed 中性呈现、无重试 | #运行状态 | 待分配 | covered | 当前有效需求 |
| C6 「分页」两条（limit 规则、不传负值/不缓存负 cursor） | complete | 分页参数与负数防护 | #分页 | 待分配 | covered | 当前有效需求 |
| C7 「分页」第三条（深分页不稳定，去重靠 ID 集合） | complete | 去重与增量判定不依赖偏移 | #分页 | 待分配 | covered | 当前有效需求 |
| C8 「轮询」第一条、第三条、第五条 | complete | 无推送；进入拉一次、60 秒、下拉刷新、离开停；只对可见行轮询 | #轮询 | 待分配 | covered | 当前有效需求 |
| C9 「轮询」第二条、第四条 | complete | 必须总带 `since`；推进取响应最大 `created_at` | #轮询 | 待分配 | covered | 当前有效需求 |
| C10 「空态与不可用能力」表六行 | complete | 无频道、无连接器、409、断网、素材 content、ask 非 LLM | #空态与错误 | 待分配 | covered | 当前有效需求 |
| C11 「鉴权」四条（Bearer、双验证、Base URL 预填可编辑、cookie 隔离） | complete | 连接流程与凭证存储 | #鉴权与连接 | 待分配 | covered | 当前有效需求 |
| C12 「Fixture」段与必须覆盖的样本情形 | complete | 测试样本必须覆盖列出的六种边界 | #测试策略 | 待分配 | covered | 当前有效需求 |

### `/var/lib/dsh/reach-news/API.md`

| 来源条目与位置 | 读取状态 | 需要保留的内容 | Spec 位置 | 验收 ID | 覆盖状态 | 理由或替代关系 |
| --- | --- | --- | --- | --- | --- | --- |
| A1 「约定」时间戳：UTC ISO 8601 带 Z、毫秒精度；`HH:MM` 按 `Asia/Shanghai` | complete | 时间解析与展示口径 | #字段归一化 | 待分配 | covered | 当前有效需求 |
| A2 「约定」分页取值规则与负 cursor 缺陷 | complete | `limit` 缺省 20/上限 100、禁止负值 | #分页 | 待分配 | covered | 当前有效需求 |
| A3 「约定」错误信封与六个已实测 code | complete | 错误解析与枚举 | #错误处理 | 待分配 | covered | 当前有效需求 |
| A4 「鉴权」：Bearer、401、管理员 cookie 隔离 | complete | 只带 Bearer，不尝试 `/admin/api/*` | #鉴权与连接 | 待分配 | covered | 当前有效需求 |
| A5 频道端点与字段（`schedule` 键、`kind`、`lastBriefAt` 可 null）；`PATCH` 只处理出现字段、运行中 409 | complete | 频道读写语义 | #频道列表 + #频道编辑 | 待分配 | covered | 当前有效需求 |
| A6 日报端点与字段（`sections[].items[]`、`memorySummary`） | complete | 日报结构 | #日报详情 | 待分配 | covered | 当前有效需求 |
| A7 素材端点与字段；`content` 为原始文件内容 | complete | 素材只取标题/URL，不渲染正文 | #日报详情 | 待分配 | covered | 当前有效需求 |
| A8 运行端点与字段；`state` 七值、`trigger` 六值、`missedReason` 仅 missed/failed 有意义 | complete | 运行状态模型 | #运行状态 | 待分配 | covered | 当前有效需求 |
| A9 `retry` 仅接受 failed/missed、`resume` 仅接受未续跑的 failed | complete | 不导出超出条件的动作 | #运行状态 | 待分配 | covered | 当前有效需求 |
| A10 Ask 端点、请求与响应；历史为 snake_case；`answer` 是确定性拼接、无 LLM | complete | 追问为确定性应答 | #追问 | 待分配 | covered | 当前有效需求 |
| A11 `POST /briefs/:id/regenerate` 返回新运行 | complete | 仅在存在日报时可用 | #运行状态 | 待分配 | covered | 与 D4 一致 |
| A12 `POST /api/v1/follows` 两种用法 | complete | 关注派生能力（本轮不提供入口） | — | — | non-goal | 稿子无关注入口，手机端不建该动作 |
| A13 `/cursor` 响应形状（snake_case、`enabled` 为整数）与「无 nextCursor」 | complete | 轮询响应归一化 | #轮询 | 待分配 | covered | 当前有效需求 |
| A14 `/health` 免鉴权响应 | complete | 连接页双验证之一 | #鉴权与连接 | 待分配 | covered | 当前有效需求 |
| A15 「已知缺口」1–8 | complete | 手机端不得假装具备的能力 | #非支持能力 | 待分配 | covered | 当前有效需求 |

### `docs/adr/` 与 `GLOSSARY.md`

| 来源条目与位置 | 读取状态 | 需要保留的内容 | Spec 位置 | 验收 ID | 覆盖状态 | 理由或替代关系 |
| --- | --- | --- | --- | --- | --- | --- |
| D1 ADR 0001 全文 | complete | 日报/频道用编辑风、追问用近单色工具风；两套 token 按界面归属选用，视图内不写字面色值 | #设计 token | 待分配 | covered | 当前有效需求 |
| D2 ADR 0002 全文 | complete | 本轮只交付 iOS；Android 保持可构建、不对齐 | #范围约束 | 待分配 | covered | 当前有效需求 |
| D3 ADR 0003 全文 | complete | 不缓存日报与素材；断网只提示无网络；只持久化 `lastSeenAt`，二者分开命名存储 | #持久化 | 待分配 | covered | 当前有效需求 |
| D4 ADR 0004「重新生成」段 | complete | 仅当存在日报时出现重新生成；不为 missed 造动作 | #运行状态 | 待分配 | covered | 当前有效需求 |
| D5 ADR 0004「频道创建」段 | complete | 新建入口保留可见，端点可用前不落地保存动作 | #频道列表 | 待分配 | covered | 当前有效需求 |
| G1 GLOSSARY 内容/运行/对话三组术语与各自的 Avoid 列表 | complete | 代码命名、界面文案与测试命名统一用该词表 | #领域模型 | 待分配 | covered | 当前有效需求 |

边界内全部条目均已读取；需要实现的条目均已有 Spec 归属。S22 为背景说明、A12 为非目标（稿子无关注入口），二者不要求 Spec 位置。

# 约束

- 构建与验收证据只能来自 GitHub Actions：本机无 Swift/Xcode/Android SDK，根文件系统只读。任何「通过」都必须能指向一次真实 CI 运行。
- 界面实现以稿子为唯一视觉依据，不自行发明稿外版式；稿子明确不含的页面（设置、连接、空态、错误态）按契约与 ADR 补齐行为，但沿用稿子的 token 与组件语汇。
- 两套视觉语言不混用：日报与频道走编辑风 token，追问走另一组 token。
- 素材 `content` 永不渲染；`missed` 不着警示色；不对确定性应答做出流式或思考中的暗示。
- `android/**` 保持字节不变，仅要求 CI 的 `assembleDebug` 继续通过。

# 关键决定

## Q1 构建与验收证据：统一走 GitHub Actions

本机根文件系统只读，没有 Swift、Xcode、Android SDK，因此本机无法编译任何一端。用户明确指定构建统一走 GitHub Actions。

- 已实测：把 `main` 推送到 `comet/baseline-probe` 后，token 可推送、仓库 Actions 已启用且 `allowed_actions: all`。
- 已实测：`main` 上最近一次运行（run 44309077235）三个任务全绿 —— iOS 设备 IPA、iOS 模拟器预览、Android `assembleDebug`。
- 已实测：**当前 workflow 没有测试步骤**（iOS 任务只做 archive）。本轮需在 iOS 任务中加入真实的测试执行，否则「单元测试通过」无证据。
- 推送分支本身不触发工作流（仅 `main` push 与 PR 触发）。验收时以 PR 触发的运行作为证据。
- 凭证只通过环境变量在推送命令中使用，不写入仓库、不写入任何产物或提交。

## Q2 「我的」标签页：收藏 + 偏好 + 连接信息

- 收藏日报列表：仅本机，不同步服务端（GLOSSARY「收藏」与 ADR 0003）。
- 偏好：界面语言、Base URL。
- 连接信息：当前服务地址与更换凭证入口，复用连接页的双验证流程。

## Q3 稿子有、服务端没有的部分：先做界面，标「功能开发中」

用户决定：凡是服务端未提供、但稿子里出现的界面，先按稿子做出来，其中依赖服务端未支持数据的位置显示「功能开发中」。这条是对 ADR 0004 既有做法的推广 —— ADR 0004 已经把「新建入口保留在视觉稿中、端点可用前不落地保存动作」定为原则。

具体落地：

- 追问页「引用的素材 · N 条」内嵌卡按稿子留位，卡内明确标注引用与归属数据待服务端支持；**不填入任何素材、不伪造引用关系**。
- 两个快捷动作（「展开素材 C」「看这期分组」）：能由现有数据支撑的直接实现，「展开素材 X」这类依赖引用关系的标为开发中。
- 频道 `+` 新建入口按稿子常驻，点击说明功能开发中（与 ADR 0004 一致，不提供会建出跑不起来频道的保存路径）。
- 与 ADR 0004 一致的部分不变：`missed` 不提供重新生成；不导出超出服务端条件的动作。

## Q4 本地化：中文为主，英文键集对齐

- `zh-Hans` 全量覆盖新界面，术语遵循 `GLOSSARY.md`。
- 新增 `en.lproj`，键集与中文完全对齐，英文为对等译文。
- 跟随系统语言，缺失译文回落中文。稿子文案为中文，中文为准。

## 后端鉴权迁移（本轮范围扩充）

后端已完成破坏性鉴权迁移：旧长期 Bearer Token 全部失效，改为 `POST /api/v1/login` 账号密码换 7 天会话凭证，并新增 `POST /api/v1/logout` 与 `429 too_many_attempts`；频道 `kind` 新增 `preset`。

用户已明确选择「本轮一并改」。据此修订：鉴权与连接一节整体改为账号密码登录，新增限流与过期处理、preset 过滤。已实现的旧 Token 流程视为被替代，不保留双轨。

## 不拆分 Supervisor

数据层与界面在同一批文件上反复修改（`BriefFeedStore` 与日报流、`ChannelStore` 与频道卡与编辑页），验收无法干净切割给并行子任务。按澄清参考，目标紧密相关、需反复修改同一核心区域时不拆分，由单个 Native Change 推进。

# 非目标

- Android 功能或视觉对齐。
- 频道创建、频道删除、关注派生入口的落地保存动作。
- 离线内容缓存、收藏同步、推送、SSE/WebSocket。
- 深色模式（稿子只有纸色；沿用 `.preferredColorScheme(.light)`）。
- 运行级「重新生成」统一动作（等 `missed` 也能触发后再做）。

## 2026-11-21 补充能力（A48 / A49）

后端就绪后新增两项客户端能力，均已实现：

### A48 手机端删除频道

- 新增 `DELETE /api/v1/channels/:id`，复用管理员页已有的 `softDeleteChannel`。
- 软删除：日报、运行、素材全部保留；列表、详情、`/cursor` 都不再出现。
- 删除别人的频道、已删除的频道，都返回 `404`；有运行在跑返回 `409`。
- 成功返回 `200 { id, deleted: true }`。
- 客户端：频道编辑页提供「删除频道」，二次确认后调用；成功后从列表移除并返回上一页；`404` 视为已删除；`409` 提示有运行未结束。

### A49 通过 API 读取时区

- 新增只读 `GET /api/v1/settings`，返回 `{ timeZone }`。
- 配置缺失或非法时回退 `Asia/Shanghai`，与调度器逻辑一致。
- 不含并发上限等管理端参数，也没有写接口。
- 客户端：用它显示「按 {timeZone} 触发」，并随配置变化；同时用它解释采集时间表与日期分组，取代硬编码的 `Asia/Shanghai`。

# 验收示例

## 外壳与导航

- 应用有日报、频道、我的三个标签，各自独立的导航栈；导航栏与标签栏为系统半透明玻璃，内容从其下方滚过。
- 导航栏品牌区显示品牌图形与「Reach News」字标。

## 日报流

- 带有效 token 启动，能看到真实频道与真实日报列表，列表按日期倒序分组，今天与昨天用相对词、更早用日期。
- 元信息行显示当天日期星期、频道总数、已加载期数与「最新优先」。
- 每条行显示标题、频道标识点与频道名、Asia/Shanghai 时刻、分组数、素材数。
- 同一 `channelId` 在列表、详情、编辑页使用同一个标识色。
- 滚动到底部自动加载下一页，加载中显示指示，到达边界显示无更多内容。
- 下拉刷新重取最新并按 ID 合并，不产生重复行。
- 搜索按标题过滤已加载内容，无匹配时显示空结果说明。

## 筛选

- 筛选面板可从底部升起，时间单选（全部/本周/本月/近三个月/自定义范围）、频道多选，页脚显示随选择实时更新的「显示 N 期」。
- 选择早于已加载边界的范围时，客户端继续加载直到覆盖范围起点或到达数据边界，再呈现结果。

## 日报详情

- 详情头部显示标题、`M月d日 HH:mm`、分组数、素材数。
- 分组标题吸顶并带背景模糊，显示分组名与「N 条」。
- 条目卡显示标题、摘要、素材数；展开后内联显示素材行。
- 素材行只显示标题与域名，点开外跳浏览器，正文从不出现在应用内。

## 追问

- 日报详情右下角有追问胶囊，静止展开、滚动收起为圆形，停止滚动后恢复。
- 追问页使用与日报不同的近单色 token 组，含日期分隔、左右气泡与底部加号/输入框/麦克风。
- 发送后直接呈现服务端返回的回答，全程没有「正在思考」或逐字输出。
- 稿件中的引用素材卡按稿子留位并显示「功能开发中」，卡内不填任何素材。

## 频道

- 频道卡显示标识点、名称、跟踪徽标、开关、提示词、状态 chip 与时间表描述。
- 切换开关即时生效；请求失败时回滚到原状态并提示原因。
- 运行中 chip 用绿色系，错过用中性灰，失败用警示色。
- 运行状态轮询只作用于屏幕内可见行，离开页面即停。
- 编辑页可改名称、提示词、口吻、时间表，连接器只读并注明需在管理后台调整。
- 保存只提交被改动的字段。
- 频道运行中保存返回 409 时，顶部出现提示且已填内容全部保留。
- 频道列表的 `+` 新建入口可见，点击说明功能开发中，不提供保存路径。

## 连接与鉴权（后端已完成破坏性迁移后）

- 首次启动无会话进入登录页：Base URL 预填 `reachapi.niuma.art` 且可编辑，填写账号与密码。
- 登录走 `POST /api/v1/login`，成功才把会话凭证写入 Keychain 并记录 `expiresAt`；失败不写入、不覆盖既有会话。
- 密码只在登录提交时使用，成功后立即从内存清空，不落盘、不写日志。
- 凭据错误统一提示，不区分「用户不存在」与「密码错误」。
- 收到 `429 too_many_attempts` 时显示锁定提示并禁用提交，**不自动重试**，冷却结束后才允许再次提交。
- 会话 7 天有效；过期或收到 401 时清本地凭证并回到登录页，不自动重试。
- 退出登录调用 `POST /api/v1/logout`，无论返回结果如何都立即清本地凭证。
- 所有 `/api/v1` 请求带 `Authorization: Bearer <会话凭证>`，且不访问 `/admin/*` 与 `/admin/api/*`。
- 频道 `kind: "preset"` 为管理员模板频道，不进入普通用户列表。

## 数据边界

- 断网时下拉刷新显示「当前无网络」，不出现任何历史内容。
- 客户端不缓存日报与素材内容；`lastSeenAt` 作为轮询基线独立命名与存储。
- 轮询总是带 `since`，并以响应中最大的 `created_at` 推进，不用本地时间。
- 分页参数永不为 0、负数或超过 100，且不缓存负 `cursor`。
- `missedReason` 与 `error.code` 的未知值保留原始字符串，不丢弃；`too_many_attempts` 已纳入枚举。
- 频道 `kind` 枚举包含 `preset`，且按可见性过滤。

## 我的

- 「我的」包含收藏列表、界面语言与 Base URL 偏好、当前服务地址与更换凭证入口。
- 收藏仅存本机，不同步服务端，可取消收藏并进入对应日报。

## 删除频道

- 频道编辑页提供「删除频道」，经二次确认后才执行。
- 删除成功后该频道从列表消失，并返回列表页。
- 服务端返回 `404`（别人的频道或已删除）时，按「已删除」处理并移除本地条目。
- 服务端返回 `409`（有运行在跑）时，提示等待运行结束，不删除。

## 与服务端一致的时区

- 频道列表副行显示「按 {服务端时区} 触发」，取 `GET /api/v1/settings` 的 `timeZone`。
- 服务端配置变化后，界面显示的时区随之变化，不是硬编码。
- 采集时间表与日期分组按服务端返回的时区解释。
- 服务端不可用或字段缺失时回退 `Asia/Shanghai`，不报错。

## 工程与交付

- 单元测试覆盖 DTO 解码、时间解析、未知枚举保留、分页参数、`lastSeenAt` 推进、筛选去重、编辑只提交改动字段与 409 不丢输入。
- `android/**` 相对改动前字节不变，且 CI 的 `assembleDebug` 通过。
- GitHub Actions 的 iOS 任务实际执行测试并给出通过结果，而非只做 archive。
- 中英文键集完全对齐，界面无硬编码文案。

# Open questions

本轮问题均已由用户明确回答，无遗留阻塞项。Q1–Q4 的结论见上方「关键决定」。
