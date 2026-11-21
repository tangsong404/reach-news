# Reach News

Reach News 的手机客户端。iOS 端连接 `reachapi.niuma.art` 的真实 `/api/v1` 接口，
不再使用内置样例数据。Android 端保持现状，仅维持可构建。

## 项目

- `ReachNews/` — SwiftUI iOS 客户端，由 `project.yml` 经 XcodeGen 生成工程。
- `android/` — Kotlin + Jetpack Compose Android 客户端（本轮未改动）。
- `Fixtures/` — 真实响应形状的样本，供单元测试与 Preview 使用。
- `docs/client-contract.md` — 客户端侧契约（归一化、状态映射、分页、轮询、鉴权）。
- `docs/adr/` — 本轮重设计的关键决策。
- `GLOSSARY.md` — 跨端共享的术语表。
- `.github/workflows/build.yml` — 构建与测试，全部在 GitHub Actions 上执行。

服务端的实测契约以 reach-news 仓库的 `API.md` 为权威。

## 结构

```
ReachNews/
  App/        入口、标签根视图、依赖装配
  Design/     语义 token 与可复用组件
  Domain/     领域模型、枚举、分页与筛选规则
  Data/       API 客户端、DTO、Keychain 与偏好存储
  State/      会话、日报流、频道、详情、追问的 Store
  Features/   日报流 / 详情 / 追问 / 频道 / 我的 / 连接
  Resources/  Assets.xcassets、zh-Hans 与 en 文案
```

## 本地构建

本仓库的构建与测试统一走 GitHub Actions；iOS 需要 macOS 与 Xcode，Android 需要
JDK 17 与 Android SDK。推送分支并开 PR 即可触发。

- `iOS Unit Tests` — `xcodebuild test`，运行 `ReachNewsTests`。
- `iOS SwiftUI Device IPA` — 生成未签名 IPA。
- `iOS Visual Preview` — 模拟器启动并截图。
- `Android Compose APK` — `./gradlew assembleDebug`。

## 配置

首次启动进入连接页：填入 Base URL（预填 `reachapi.niuma.art`）与管理员签发的
Bearer Token。客户端先检查 `/health`，再验证 `/api/v1/channels`，两项都通过才把
Token 写入钥匙串。
