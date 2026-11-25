# Android 用 Vue 3 + Vite + Capacitor，与可及清单同一技术栈

ADR 0002 约定 iOS 定型、契约与 fixture 固化之后，Android 按契约实现。这一轮落地 Android 时，没有沿用原先单文件的 Kotlin + Compose 移植，而是改用与可及清单（reachlist）相同的技术栈：Vue 3（`<script setup>`、纯 JS）+ Vite + Capacitor 8，存储用 `@capacitor/preferences`，网络用开启 `CapacitorHttp` 的 `fetch`。

理由：

- 原 Kotlin 客户端只有 145 行静态样例，没有可复用的状态层或数据层，重写成本与换栈相当。
- 与可及清单共用同一套基础设施写法（底部弹窗、安卓返回键栈、键盘逐帧跟随、以中文原文为键的 i18n、`package.json` 单处维护版本号），维护者只需熟悉一套。
- 领域层（`src/lib/model.js`、`src/lib/time.js`）是不依赖框架的纯函数，可直接用 `node --test` 覆盖契约里的归一化、分页、轮询基线与可写性规则，样本仍取自仓库根目录的 `Fixtures/`。
- 服务端不开 CORS；`CapacitorHttp` 让请求走原生网络栈，WebView 不受同源限制。

保持不变的部分：视觉 token 沿用 iOS 的编辑风 / 追问风两套（ADR 0001），不缓存内容（ADR 0003），不把服务端尚未支持的能力包装成按钮（ADR 0004），包名仍为 `com.tangsong404.reachnews`。

**放弃的方案**：继续 Kotlin + Compose（与团队另一款 Android 应用的栈不一致，且需要从零搭状态层）；React Native / Expo（比 Capacitor 重，且与可及清单不一致）。
