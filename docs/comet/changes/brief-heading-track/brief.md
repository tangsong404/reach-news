# 目标

日报详情页的正文有两处需要改动。

1. **正文链接可辨**：当前正文里的行内链接能点，但与正文同色（全局 tint 是近黑色 `Palette.ink`），在纸色底上等于看不见。
   用户实机试用后明确：**不要蓝色着色**，改为**下划线 + 外链图标**（SF Symbols `arrow.up.forward.app`），文字保持正文色，点击行为不变（仍用系统浏览器打开）。
   **每条链接后面都要跟一个图标**，不是整段只有末尾一个。
2. **小标题后面跟「follow」按钮**：小标题本身**不加下划线、不可点**，保持普通标题样式；按钮文字为 **follow**，**紧跟标题文字之后**（不是贴在小标题整块的右边，也不是加号图标）。点该按钮**直接进入频道创建页**，不弹窗、不需要二次选择。
   创建页沿用事件模式：标题取小标题文字，提示词预填跟踪该事件的模板，二者均可修改后按普通频道提交。
   **去掉「查看原文」**：本轮不再提供跳转原文的入口，也不再需要把标题与素材做匹配（用户已明确取消该功能）。

3. **账号头部接入真实数据 + 修复用户名不显示**：用户实机发现「我的」页用户名是空的。账号头部改读后端真实字段（`GET /api/v1/me` 的 `name` / `email` / `tier` / `avatarUrl` / `capabilities`），套餐按服务端实际取值建模（实测有 `admin` / `free` / `ultra`，**无 `pro`**），未知档也原样显示不映射成 ultra，头像用 `avatarUrl`（`null` 时缺省），并支持 `POST /api/v1/me/avatar` 上传。

3b. **账号卡片与个人页**（用户实机反馈）：
   - 账号卡片**加大**（头像与字号放大），并减少卡片上方与顶部栏之间的空白。
   - 套餐标识做成**标签样式**（胶囊/圆角底），按档位配色：`admin` 紫、`ultra` 金、`free` 中性灰。
   - 去掉「我的」页里的「连接信息」入口；改由**点账号卡片进入个人页**承载。
   - 个人页提供：**切换昵称、修改头像（含删除头像）、修改密码、退出登录**。
   - **换绑邮箱入口去掉**：服务端没有换绑邮箱接口，用户也不要求。
   - 后端已就绪（`PATCH /api/v1/me`、`POST /api/v1/me/password`、`DELETE /api/v1/me/avatar`），这三项从「置灰占位」改为**真实可用**；错误按服务端 code 与中文 message 展示。
   - 改密码成功后**不踢回登录页**：实测服务端采用方案 A（其他设备失效、当前 token 保留）。

4. **注册页与登录改造**：按 `api-changes-invite-registration.md` 与 `api-changes-account-and-email.md` 增加邀请码注册（昵称/邮箱/密码/确认密码/邀请码），注册成功直接进 App；登录改为接受邮箱或昵称；两者都消费 `user` 与 `capabilities`。
   - **图形验证（hCaptcha）**：进注册页先调 `GET /api/v1/auth/captcha` 取 `{ enabled, siteKey }`；`enabled` 为真时必须先完成人机验证拿到 token，再随注册提交 `captchaToken`。实测生产已启用，所以这是主流程而非可选分支。
   - **邮箱验证码**：是否必需取决于管理员是否配了 SMTP。客户端按「可能需要」处理：点发送验证码 → `POST /api/v1/auth/email-code`（`purpose: "register"` + captchaToken）→ 拿到后随注册提交 `emailCode`；若返回 `mail_not_configured`(503) 则不提交该字段。
   - **错误必须逐项可读**：`code_too_frequent`(429，带 `retryAfterSeconds`，做倒计时)、`code_hourly_limit`、`captcha_required`/`captcha_failed`、`code_mismatch`/`code_expired`/`code_too_many_attempts`、`mail_not_configured` 等，优先展示服务端中文 `message`。

# 范围

## 目录结构

### 新建

- `ReachNews/Features/Me/AccountDetailView.swift`：账号卡片点进去的个人页，承载切换昵称、修改头像（含删除）、修改密码、退出登录。
- `ReachNews/Features/Auth/RegisterView.swift`：邀请码注册页（昵称、邮箱、密码、确认密码、邀请码），按服务端 code 逐项提示。
- `ReachNews/Domain/UserProfile.swift`：当前用户与能力模型（`name` / `email` / `tier` / `avatarUrl` / `capabilities`）。
- `ReachNewsTests/RegistrationTests.swift`：覆盖注册请求编码、错误码到提示的映射、注册成功直接建立会话。
- `ReachNews/Features/BriefDetail/BriefHeadingActions.swift`：小标题右侧「跟踪」按钮，以及事件预填内容（标题与提示词）的生成。
- `ReachNewsTests/BriefHeadingTests.swift`：覆盖事件预填标题与提示词的生成。

### 修改

- `ReachNews/Data/APIClient.swift`：新增 `POST /api/v1/register`、`GET /api/v1/me`、`POST /api/v1/me/avatar`、`GET /api/v1/users/:id/avatar`。
- `ReachNews/Data/DTO/DTOs.swift`：登录响应解析新增 `email` / `tier` / `avatarUrl` 与 `capabilities`；新增注册与 me 的 DTO。
- `ReachNews/State/SessionStore.swift`：登录接受邮箱或昵称；新增注册成功后的建会话路径；恢复会话后拉 `/api/v1/me`。
- `ReachNews/State/ProfileStore.swift`：用户名/邮箱/套餐/头像改读真实字段，删除本地占位常量；套餐改 `free` / `ultra` 两档。
- `ReachNews/Features/Me/AccountHeaderView.swift`：卡片加大；套餐改为标签样式并按档位配色；整卡可点进个人页；头像按 `avatarUrl` 加载，`null` 与加载失败都回退缺省头像。
- `ReachNews/Features/Me/MeView.swift`：移除「连接信息」入口，改由账号卡片进入个人页。
- `ReachNews/Design/Components.swift`：新增套餐标签组件（胶囊 + 按 tier 取色）。
- `ReachNews/Features/Connection/ConnectionView.swift`：登录页增加进入注册页的入口。
- `ReachNews/Features/BriefDetail/MarkdownBodyView.swift`：小标题右侧渲染「跟踪」按钮（标题本身不加下划线、不可点）；链接改为下划线 + 外链图标（`arrow.up.forward.app`）。
- `ReachNews/Features/BriefDetail/BriefBodyView.swift`：把「跟踪」回调传下去。
- `ReachNews/Features/BriefDetail/BriefDetailView.swift`：承载「跟踪」跳转到创建页。
- `ReachNews/Features/Channels/ChannelCreateSheet.swift`：支持事件模式入参（标题与提示词预填），普通新建行为不变。
- `ReachNews/Features/Channels/ChannelListView.swift`：创建页的既有调用点保持行为不变。
- `ReachNews/Design/Components.swift`：若链接图标样式需要复用，放在这里。
- `ReachNews/Resources/zh-Hans.lproj/Localizable.strings`、`ReachNews/Resources/en.lproj/Localizable.strings`：新增动作名称、事件提示词模板与相关键，两侧保持对齐。

### 明确不建

- 不做「查看原文」：不提供跳转原文入口，也不再把小标题与素材做标题匹配（用户已取消该功能）。
- 不请求「小标题到素材」的关联数据，不改后端返回结构。
- 不做「事件」这种新的频道类型或新的后端实体；事件仍是一个普通频道，只是创建时预填内容。
- 不改日报列表、频道列表等其它页面（日报详情见第 1、2 条）。
- 不引入 `pro` 档：文档明确它已被取消。
- 不做邮箱验证（服务端明确不验证）。
- **退出登录**：复用既有「我的 → 连接信息」中的退出入口，但接入新会话后必须同时清掉 `/me` 拉取的用户资料、能力状态与头像缓存，回到登录页；不得残留上一个账号的头部信息。
- 注册流程内不提供头像上传（服务端刻意如此）。

# 非目标

- 不改 `android/**`。
- 不改订阅与运行逻辑。
- **API 地址固定**：移除登录页与偏好里的 Base URL 输入，地址固定为 `https://reachapi.niuma.art`。
- 不改正文的 Markdown 解析规则与分块逻辑（只为小标题增加右侧「跟踪」按钮）。
- 不改分页、轮询与错误映射。

# 验收示例

- 正文里的行内链接在纸色底上视觉可辨（有颜色区分或下划线），点击仍由系统浏览器打开其 `url`。
- 正文小标题**不显示下划线、不可点击**，保持普通标题样式；标题右侧显示一个「跟踪」按钮。
- 点击标题右侧的「跟踪」按钮**直接进入频道创建页**，不出现任何弹窗或选择步骤。
- 界面上**不存在**「查看原文」入口，也不再为它做标题与素材的匹配。
- 「跟踪」按钮在任何小标题上都出现（不依赖素材数据），点击后创建页的名称与提示词均已预填。
- 创建页的名称等于该小标题文字，提示词等于跟踪该事件的预填模板。
- 预填的标题与提示词都可被用户直接修改，提交后按普通频道创建。
- 普通入口（频道页的 +）新建频道时，名称与提示词仍为空，不出现任何预填内容或事件模式痕迹。
- 不再有任何标题↔素材匹配逻辑；相关代码与类型应删除，不留下死代码。
- 中文与英文本地化键集完全一致，新增键两侧同时存在，界面无硬编码文案。
- 单元测试覆盖事件预填的标题与提示词生成；不再有匹配相关测试。
- 正文链接不再使用颜色区分：链接文字为正文色，带下划线，并在文字后显示外链图标（SF Symbols `arrow.up.forward.app`）；点击仍由系统浏览器打开。
- 「我的」页冷启动后用户名可见：会话恢复后立即取 `/api/v1/me`，取到前显示占位而不是空行。
- 套餐标识显示服务端 `tier` 原值（实测含 `admin`），客户端与界面均不出现 `pro`，也不把管理员档映射成 ultra。
- `email` 为 `null` 时显示缺省占位，不出现空白行或字面 `null`。
- 头像请求返回 404 `avatar_not_found` 时按「没有头像」显示缺省图形。
- 追问入口、建频道上限按 `capabilities.ask` 与 `capabilities.channelLimit` 决定；`channelLimit` 为 `null` 时不限。
- 头像按 `avatarUrl` 加载；`null` 或加载失败显示缺省头像，不出现空白圆或破图。
- 登录页可进入注册页；注册成功直接进入 App，不再调用登录接口。
- 注册失败按服务端 code 给出逐项提示（邀请码、昵称、邮箱、密码四类），不使用笼统网络错误文案。
- 创建频道超出上限时按 `channel_quota_exceeded` 提示「已达上限」，不当成网络错误。
- 单元测试覆盖注册请求编码与错误码到提示的映射。
- 退出登录后回到登录页，且「我的」页不再残留上一账号的用户名、邮箱、套餐与头像；重新登录另一账号时不显示旧账号信息。
- 本机用 tree-sitter 静态解析全部 `.swift` 无新增 `ERROR` 节点；CI 结果出来前，构建与测试相关结论记为 `not-run`，不记为通过。
