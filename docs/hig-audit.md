# HIG 审计与修复验收报告

> **更正：下表是历史批次记录，不代表当前版本已逐项验收通过。** 后续实测发现导航、行距、品牌位置等回归。此前以源码计数和编译成功推断交互正确并不充分。当前修复须由真实 simulator UI tests（文章点击、键盘输入、滚动与页面截图）提供证据；不能用 ImageRenderer 或 CI 编译成功替代完整交互验证。

## 当前四项回归修复（待本批 CI 交互证据）

| 问题 | 根因/修改 | 当前结论 |
|---|---|---|
| 原生搜索框式提问输入 | 使用 UIKit `UISearchBar` 的系统搜索输入外观；键盘返回键为发送，保留单独发送按钮和右上角追问入口 | 实现已改，待模拟器截图/交互 |
| 品牌应在搜索框上方 | 品牌、原生搜索框、数量、日期、文章放入同一个纵向内容流，按此顺序排列；移除导航栏 search drawer 导致的反序 | 实现已改，待几何断言/截图 |
| 数量/日期/正文大空隙 | 原 List 把很矮的标签提升到默认行高；正文又自带垂直 padding，形成叠加。首页改回单一 ScrollView，标签不再承担 List 行约束 | 实现已改，待几何断言 |
| 文章无法打开 | 移除列表父级 SwiftUI TapGesture；文章行明确执行 path.append，仍由同一 NavigationStack 的 typed destination 承载。全局收键盘改为不取消原触摸、过滤输入控件的观察器 | 实现已改，待实际点击进入/返回/重复打开 |


审计依据：Apple Human Interface Guidelines（skill release 2026-09-27，Apple 快照 2026-09-12），平台 iOS / iPadOS，任务类型 audit。
修复分支：`comet/brief-heading-track`，候选提交 `68f7979`，CI run `45912711040`（四个 job 全部 success）。

状态口径：

- **已改**：代码层面完成，可用静态检查与 CI 复现。
- **已改（待真机）**：代码完成、CI 通过，但最终观感/手感只能真机确认。
- **按设计保留**：与既有产品决定冲突，工程上做了折中并在下面写明。

| # | 项目 | 状态 | 落点 | 证据 |
|---|---|---|---|---|
| 1 | Dynamic Type | 已改（待真机） | `Tokens.swift:280` `TypeFace.scaledSize` | 全站字体统一经 `UIFontMetrics(forTextStyle:.body)` 按系统字号缩放；字号下限抬到 11pt；`ReachNewsApp` 读取 `dynamicTypeSize` 让整树重算 |
| 2 | 三级文字对比度 | 已改 | `Tokens.swift:72` | 亮色 4.70:1（奶油底）/ 5.39:1（白底），暗色 7.33:1（卡片）/ 8.86:1（画布） |
| 3 | 44pt 点击区 | 已改（待真机） | `MarkdownBodyView.swift:275`、`MeView.swift:330`、`Components.swift:427/544` | 铃铛、主题色点、选色格、开关均为 44×44；已删除 34pt 自绘导航圆钮 |
| 4 | 自定义按钮按压态 | 已改 | `Components.swift:561` `PressableButtonStyle` | `.buttonStyle(.plain)` 0 处残留，29 处改为 `.pressable` |
| 5 | Reduce Motion | 已改 | `AskView.swift:13`、`ChannelListView.swift:13`、`AccountDetailView.swift:18` | 滚动定位、发现更多展开、toast 过渡在开启减弱动态效果时不做动画 |
| 6 | 提高对比度变体 | 已改 | `Tokens.swift:105` | `Color(light:dark:highContrastLight:highContrastDark:)`，ink / inkSecondary / inkTertiary 各有高对比取值；分隔线与填充改用系统色自动继承 |
| 7 | 标签栏可见性 | 已改 | 全仓 | `toolbar(.hidden, for: .tabBar)` 0 处 |
| 8 | 标签栏填充图标 | 已改 | `RootTabView.swift:53/63/73` | `list.bullet.rectangle.fill` / `rectangle.stack.fill` / `person.crop.circle.fill` |
| 9 | 大标题 | 已改 | `BriefFeedView.swift:25`、`ChannelListView.swift:27`、`MeView.swift:15` | 三个一级页面 `.large` + `navigationTitle`；详情页保持 inline |
| 10 | 列表用 List | 已改 | `BriefFeedView.swift:191`、`ChannelListView.swift:157` | 日报流与频道页改为 `List` + `Section`，分隔线/行高亮/滑动操作交回系统 |
| 11 | 系统搜索框 | 已改 | `BriefFeedView.swift:85` | `.searchable(text:placement:.navigationBarDrawer(displayMode:.always), prompt:)`，自绘搜索行已删除 |
| 12 | 收藏角标 | 已改 | `MeView.swift:30/54` | 去掉 `.badge(count)`，数量并入行标题 |
| 13 | 频道开关 | 已改 | `Components.swift:528` | 卡片内不再用开关样式，改为 toggle 形态按钮（勾选/空心两态 + accent 着色 + 44pt 可点） |
| 14 | 返回按钮 | 已改 | 全仓 | 自绘 34pt 圆形导航按钮已删除，`navigationBarBackButtonHidden` 0 处，全部用系统返回 |
| 15 | 追问入口 | 已改 | `BriefDetailView.swift` 工具栏 | 浮动胶囊（FAB）删除，改为导航栏气泡按钮，不再遮挡正文 |
| 16 | 颜色语义复用 | 已改 | `Tokens.swift:131` | 新增 `inverseSurface` / `onInverse`，toast 与「新」标记不再借用正文色作底色；`fill(Palette.ink)` 0 处 |
| 17 | 系统语义色 | 已改（有保留） | `Tokens.swift:122/126` | 分隔线用 `.separator` / `.opaqueSeparator`，chip/field 用 `.tertiarySystemFill`；品牌底色 `canvas`/`surface` 保留自绘（见下） |

## 需要说明的两处折中

**17 · 品牌底色保留自绘。** HIG 原文是 “Prefer system-defined colors”。本项目的画布与卡片色是「编辑风暖纸 / 简洁风纯白」两套风格的基础，直接用 `systemBackground` 会把用户此前确认的风格差异抹平。因此只把*功能件*（分隔线、填充、标签色）换成系统语义色，品牌底色保留，并且这些自绘色本身已提供亮/暗与高对比四套取值。

**18 · 应用内外观设置保留。** HIG（Dark Mode）不推荐应用自定义外观开关：

> “Avoid an app-specific appearance setting; it makes people manage two settings and may appear broken when it ignores the system choice.”

按你的要求（A27 起）保留「亮色 / 暗色 / 跟随系统」，默认仍是「跟随系统」。若以后要完全贴合 HIG，只需删掉这一项，其余代码无需改动。

## 仍未覆盖 / 需真机确认

- 大字号下的版面（AX1–AX5）：代码已跟随缩放，换行与截断只能真机看。
- `List` 化后的视觉效果（分组间距、分隔线、行高亮）与 `searchable` 的收起/展开动画。
- 频道卡片作为 List 行之后的行高与内边距。
- 44pt 命中区在行内是否互相重叠（铃铛与标题、主题色点之间）。
