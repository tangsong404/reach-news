# 本轮只做 iOS，Android 仅保持可构建

客户端重设计只交付 iOS。Android 保持现有代码、仅确保 `assembleDebug` 通过，不新增功能、不与 iOS 对齐；契约文档与 fixture 先行写好，供下一轮 Android 使用。

背景：Android 现状是单文件 145 行的 Compose 移植，无状态层、无持久化、无测试、无本地化，且样例数据的 id 已与 iOS 漂移（`iran` vs `iran-ceasefire`）。两端同时从零重写会把交付推迟到所有交互细节定稿之后，而这些细节恰恰要在真机上才能看出来。

因此顺序是：iOS 定型 → 契约与 fixture 固化 → Android 按契约实现。契约先行是为了避免重演当前的 id 漂移。

**放弃的方案**：双端同步重做（成本翻倍且并行讨论两套 UI 框架）；Android 完全不管（会让契约失去第二个消费者，容易写成只适配 SwiftUI 的形状）。
