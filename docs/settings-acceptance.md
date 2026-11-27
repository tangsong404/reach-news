# 分组设置与文字大小验收报告

## 最新批次：连续滑条与中等密度

候选 `d900e0f`；CI [45959291667](https://github.com/tangsong404/reach-news/actions/runs/45959291667)，五项任务全成功。

| 用户要求 | 结论 | 实际证据 |
|---|---|---|
| 原生滑条 | 通过 | UI找到原生Slider并实际拖到80%轨道位置；连续90%–115%，默认100%；原三档记录迁移；单测覆盖小数值持久化、夹取、NaN与Infinity |
| 中等密度 | 通过（所测页面） | 设置行内容minHeight从44降28，最终行保留52基准，分组spacing16；UI断言普通风格行≤64pt；首页/频道辅助字体增大并放松间距；检查截图我的、外观与阅读、plain详情 |
| 删除预览 | 通过 | UI断言preferences-text-preview不存在，截图无预览区 |
| plain标题层级 | 通过 | detail标题Bold，小标题Semibold，正文Regular；SwiftUI与TextKit使用同一解析字体；真实plain详情截图确认 |
| 用户卡边框 | 通过 | 恢复完整圆角背景卡片及lineStrong细边框，真实我的页截图可见；亮暗动态色 |

第一轮UI失败：父行标识覆盖Slider标识，原生Slider无法按ID定位。已删掉父标识保留Slider标识，最终全套UI成功；失败记录不抹掉。

截图：主工作区 `dist/density-45959291667/`。范围仍是iPhone 17 Pro离线fixture，不等于所有设备/生产接口均验收。

以下保留上一批历史结果；其中三档菜单与预览区已由本批替代，不代表现状。

代码候选 `8eedf29`，CI [45944498863](https://github.com/tangsong404/reach-news/actions/runs/45944498863)。

## 验收结果

| 项目 | 结果 | 实际证据/范围 |
|---|---|---|
| 删除首页数量行 | 通过 | UI 测试断言 feed-meta 不存在；文章打开/返回/重开仍通过 |
| 内嵌分组布局 | 通过（所测页面） | 原生 insetGrouped，组标题在卡外，行首28pt图标列、标题17pt、值15pt；真实截图检查我的、账号、昵称、密码、外观与阅读 |
| 改名外观与阅读 | 通过 | 中文入口/导航标题一致；英文 Appearance & Reading；新增本地化键中英一致 |
| 文字大小三档 | 通过 | small .94 / standard 1 / large 1.08；即时UI菜单切换，阅读预览重新布局；默认 standard |
| 持久化 | 单测通过 | ReadingTextSizeTests 重建 AppearanceStore、独立 UserDefaults 实例重建，读取已存选择；不是伪称离线fixture跨App启动持久化 |
| 尊重系统字号 | 通过（限定范围） | resolved typography 同时读取 readingTextSize 与 dynamicTypeSize，经 UIFontMetrics 缩放一次；测试 .large/.xxxLarge/AX3/AX5；AX5真实页面截图已检查 |
| 字体角色统一 | 实施并检查 | 去掉全局 serif；设置主标题17/值15/辅助13；通用AppTypography处理静态TypeFace无法读取环境的问题；Markdown/TextKit共享解析后的UIFont；系统导航/图标不随App三档同比放大 |
| 帮助与关于 | 通过 | 入口→同名占位页→可返回，不新增未定义业务；只有“内容待补充” |
| 亮暗外观 | 通过（编辑风） | 我的/外观与阅读亮暗整屏截图；卡片颜色仍遵循当前主题，不照搬参考图白卡到暖纸主题 |
| 图标列大字号越界 | 已修复并复验 | 第一轮AX5截图发现图标挤出28pt列；固定视觉20pt后重新截图，保持文字放大与值纵向堆叠 |
| 既有导航回归 | 通过 | 文章点击、键盘可见时点文章、详情提问输入聚焦/收键盘、标签栏只在主页面显示 |

## CI 实际执行

- 五个任务最终成功：iOS Unit Tests、iOS Offline UI Regression Tests、iOS Visual Preview、iOS Device IPA、Android。
- 第一次最终候选UI任务在 `testArticleTapWhileSearchKeyboardIsVisible` 查询快照时超时（不是断言通过），已按失败如实保留；相同代码重跑后成功。不隐去该超时。
- UI测试为DEBUG离线fixture，使用真实SwiftUI/UIKit页面与iPhone 17 Pro模拟器，没有生产账号或网络。
- 截图为真实设备截图附件，不是ImageRenderer。

## 限制

不是全设备、全语言、所有屏幕尺寸均验证。AX5截图覆盖外观与阅读首屏和行宽，不能据此声明所有页面/编辑状态无截断。生产头像上传、昵称/密码变更接口未在离线UI测试提交。字号持久化证据是单元测试UserDefaults重建，并非UI fixture的进程重启（fixture使用隔离内存偏好）。

## 参考截图

当前截图位于主工作区 `dist/settings-45944498863/`，包括我的、账号、昵称、密码、外观与阅读亮/暗、大字号与帮助页。
