# 目标

在「我的」页最上方增加一条账号头部，样式参照用户提供的参考图：左侧圆形头像，右侧三行文字，行尾一个右向箭头。

- 第一行：用户名（当前登录用户名）。
- 第二行：邮箱。当前后端没有该字段，统一显示缺省示例地址 `name@example.com`。
- 第三行：参考图中的「信任等级 n」改为套餐标识，取值 `free` / `pro` / `ultra`；当前没有后端，统一显示 `ultra`。
- 头像本轮固定显示缺省图形，不提供选图入口（用户已确认：选图等后端就绪再做）。

用户确认的三项决定：

- Q1 → 本轮只显示缺省头像，不做相册选图。
- Q2 → 第二行缺省邮箱显示示例地址 `name@example.com`。
- Q3 → 保留行尾箭头，但点击整行本轮不响应。

# 范围

## 目录结构

### 新建

- `ReachNews/Features/Me/AccountHeaderView.swift`：「我的」页顶部的账号头部（圆形头像 + 用户名 + 邮箱 + 套餐标识 + 行尾箭头），只读呈现。
- `ReachNews/State/ProfileStore.swift`：账号资料状态，集中给出用户名回退值、缺省邮箱与套餐标识，避免视图里散落常量。
- `ReachNewsTests/ProfileStoreTests.swift`：覆盖用户名回退、套餐标识恒为 `ultra`、缺省头像判定。

### 修改

- `ReachNews/Features/Me/MeView.swift`：在「收藏 / 偏好 / 连接信息」列表之前插入账号头部。
- `ReachNews/Domain/Enums.swift`：新增套餐枚举 `PlanTier`（`free` / `pro` / `ultra`），当前无后端时取值恒为 `.ultra`。
- `ReachNews/Data/Storage.swift`：`PreferencesStoring` 增加「上次登录用户名」。冷启动从 Keychain 恢复会话时 `AuthSession.userName` 为空，头部需要靠它显示名字。
- `ReachNews/State/SessionStore.swift`：登录成功与恢复会话时把用户名写入上面的偏好项（只存展示名，不碰凭证）。
- `ReachNews/App/AppEnvironment.swift`：装配 `ProfileStore` 并注入。
- `ReachNews/Resources/zh-Hans.lproj/Localizable.strings`、`ReachNews/Resources/en.lproj/Localizable.strings`：新增账号头部相关键，两侧保持对齐。

### 明确不建

- 不新增任何服务端用户资料请求或 `/api/v1/...` 端点调用。
- 不做相册选图、头像上传、图片裁剪或压缩（用户已确认本轮不做）。
- 不做用户名、邮箱的编辑入口。
- 不做 `free` / `pro` / `ultra` 的切换、支付或购买入口。
- 不做点击整行进入的个人资料页（用户已确认本轮点整行不响应）。

# 非目标

- 不改 `android/**`。
- 不改鉴权流程、凭证存储与登录/注销的判定逻辑；只额外记录一个用于展示的用户名。
- 不改「收藏」「偏好」「连接信息」三个既有入口及其页面。
- 不改日报、频道、追问等其它页面。
- 不在服务端增加用户资料字段（等后端具备能力后再接入真实头像、邮箱与套餐）。

# 验收示例

- 「我的」页内容最上方出现账号头部，位于「收藏 / 偏好 / 连接信息」列表之前，这三项的位置与行为不变。
- 头部左侧是圆形头像；本轮固定显示缺省头像图形，不出现空白圆、破图或选图按钮。
- 头部第一行显示当前登录用户名；冷启动从已保存会话恢复时仍显示上次登录的用户名，不出现空行或占位符。
- 头部第二行显示示例邮箱 `name@example.com`。
- 头部第三行显示 `ultra`；界面上不再出现「信任等级」字样。
- 头部行尾显示右向箭头；点击整行本轮不触发任何导航、网络请求或状态变化。
- 套餐标识按 `free` / `pro` / `ultra` 三值建模，当前取值恒为 `ultra`，界面不提供切换或购买入口。
- 本轮不请求任何用户资料接口：代码中无新增的用户/资料相关 `/api/v1/*` 端点调用。
- 中文与英文本地化键集完全一致，新增键两侧同时存在，界面无硬编码文案。
- 单元测试覆盖用户名回退、套餐标识取值与缺省头像判定。
- 本机用 tree-sitter 静态解析全部 `.swift` 无新增 `ERROR` 节点；CI 结果出来前，构建与测试相关结论记为 `not-run`，不记为通过。
