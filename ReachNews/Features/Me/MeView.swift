import SwiftUI

// MARK: - 我的
//
// 收藏（仅本机）+ 偏好 + 连接信息。

struct MeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @State private var showsPlanUnavailable = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content(env)
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MainPageHeading(title: L10n.string("tab.me", locale: locale))
                        .accessibilityIdentifier("main-heading-me")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsPlanUnavailable = true
                    } label: {
                        Image(systemName: "creditcard")
                    }
                    .accessibilityLabel(Text(L10n.string("me.plan.title", locale: locale)))
                    .accessibilityIdentifier("me-plan")
                }
            }
            .alert(L10n.string("me.plan.title", locale: locale), isPresented: $showsPlanUnavailable) {
                Button(L10n.string("common.done", locale: locale), role: .cancel) {}
            } message: {
                Text(L10n.string("me.plan.unavailable", locale: locale))
            }
            .navigationDestination(for: MeDestination.self) { destination in
                switch destination {
                case .saved:
                    SavedBriefsView(saved: env.saved)
                case .preferences:
                    AppearanceReadingView(preferences: env.preferences)
                case .account:
                    AccountDetailView(session: env.session)
                case .help:
                    HelpAboutView()
                }
            }
        }
    }

    private func content(_ env: AppEnvironment) -> some View {
        List {
            Section {
                Button { path.append(MeDestination.account) } label: {
                    AccountHeaderView(profile: env.profile)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("me-account-card")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .buttonStyle(.pressable)
                .background(Theme.surface(for: env.appearance.style), in: RoundedRectangle(cornerRadius: Radius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.medium)
                        .strokeBorder(Palette.lineStrong, lineWidth: 1)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                SettingsSectionHeader(title: L10n.string("me.account.heading", locale: locale))
            }

            Section {
                VStack(spacing: 0) {
                    Button { path.append(MeDestination.saved) } label: {
                        SettingsRow(
                            title: L10n.string("me.saved", locale: locale),
                            systemImage: "bookmark",
                            value: env.saved.savedIDs.isEmpty ? nil : String(env.saved.savedIDs.count)
                        )
                    }
                    .accessibilityIdentifier("me-saved")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider().padding(.leading, 58)

                    Button { path.append(MeDestination.preferences) } label: {
                        SettingsRow(title: L10n.string("me.preferences", locale: locale), systemImage: "textformat.size")
                    }
                    .accessibilityIdentifier("me-preferences")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider().padding(.leading, 58)

                    Button { path.append(MeDestination.help) } label: {
                        SettingsRow(title: L10n.string("me.help", locale: locale), systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("me-help")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.pressable)
                .background(Theme.surface(for: env.appearance.style), in: RoundedRectangle(cornerRadius: Radius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.medium)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                SettingsSectionHeader(title: L10n.string("me.settings.heading", locale: locale))
            }

        }
        .settingsListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        .accessibilityIdentifier("me-list")
    }

}

enum MeDestination: Hashable {
    case saved
    case preferences
    case help
    /// 账号卡片点进去的个人页：资料、头像、密码与退出登录都在这里。
    case account
}

// MARK: - 收藏列表
//
// 数据来自 `SavedFeedStore`：按 ID 逐条拉取，不依赖首页已加载内容。
// 因此无论列表翻到哪一页、或重进 App，收藏都不会消失。

struct SavedBriefsView: View {
    let saved: SavedStore
    @AppTypography private var typography
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    /// 逐条拉取失败的提示文案（按 id）。
    private var savedIDs: Set<String> { saved.savedIDs }

    private var briefs: [Brief] { env.savedFeed.briefs(for: savedIDs) }

    /// 还有内容没取回来（首屏加载中）。
    private var isLoadingAny: Bool { !env.savedFeed.loadingIDs.isEmpty }

    var body: some View {
        Group {
            if savedIDs.isEmpty {
                emptyState
            } else if briefs.isEmpty && isLoadingAny {
                LoadingLine(text: L10n.string("common.loading", locale: locale))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if briefs.isEmpty {
                // 有收藏但一条都没取回来：给出可重试的失败态，而不是谎报为空。
                MessageStateView(
                    title: L10n.string("me.saved.loadFailed.title", locale: locale),
                    message: L10n.string("me.saved.loadFailed.message", locale: locale),
                    kind: .empty,
                    actionTitle: L10n.string("common.retry", locale: locale),
                    action: { Task { await env.savedFeed.refresh(ids: savedIDs) } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        .navigationTitle(L10n.string("me.saved", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Brief.self) { brief in
            BriefDetailView(brief: brief, store: env.makeDetailStore(brief: brief))
        }
        .task {
            await env.savedFeed.load(ids: savedIDs)
        }
        .accessibilityIdentifier("saved-list")
        // 只有三个一级页面保留标签栏，推入的页面全部隐藏（用户确认）。
        .toolbar(.hidden, for: .tabBar)
    }

    private var emptyState: some View {
        MessageStateView(
            title: L10n.string("me.saved.empty.title", locale: locale),
            message: L10n.string("me.saved.empty.message", locale: locale),
            kind: .empty
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(briefs) { brief in
                NavigationLink(value: brief) {
                    row(for: brief)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surface(for: env.appearance.style), in: RoundedRectangle(cornerRadius: Radius.medium))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .swipeActions {
                    Button(role: .destructive) {
                        saved.toggle(brief.id)
                        // 立即从收藏页移除，不等下次刷新。
                        env.savedFeed.forget(id: brief.id)
                    } label: {
                        Label(L10n.string("me.saved.remove", locale: locale), systemImage: "bookmark.slash")
                    }
                }
            }

            // 仍在取回或取回失败的条目单独列出来，避免用户以为收藏丢了。
            ForEach(pendingIDs, id: \.self) { id in
                pendingRow(for: id)
            }
        }
        .settingsListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        .refreshable {
            await env.savedFeed.refresh(ids: savedIDs)
        }
    }

    /// 还没成功取回的收藏 id（保持稳定顺序，避免刷新时跳动）。
    private var pendingIDs: [String] {
        savedIDs
            .filter { env.savedFeed.briefsByID[$0] == nil }
            .sorted()
    }

    private func pendingRow(for id: String) -> some View {
        HStack(spacing: Space.s) {
            if env.savedFeed.didFail(id) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.failedForeground)
                Text(L10n.string("me.saved.rowFailed", locale: locale))
                    .font(typography.body(15))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 0)
                Button {
                    Task { await env.savedFeed.retry(id: id) }
                } label: {
                    Text(L10n.string("common.retry", locale: locale))
                        .font(typography.label(12))
                }
                .buttonStyle(.pressable)
            } else {
                ProgressView().controlSize(.small)
                Text(L10n.string("common.loading", locale: locale))
                    .font(typography.body(15))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    private func row(for brief: Brief) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(brief.title)
                .font(typography.heading(17))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            if let summary = brief.displaySummary {
                Text(summary)
                    .font(typography.body(15))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 7) {
                ChannelDot(channelID: brief.channelID, colorIndex: env.channelColors.colorIndex(for: brief.channelID))
                Text(brief.channelName ?? "")
                    .font(typography.label(13))
                    .foregroundStyle(Palette.inkSecondary)
                DotSeparator()
                MetaLine(text: DisplayTime.monthDayTime(brief.createdAt, locale: locale))
            }
        }
        .padding(.vertical, Space.xxs)
    }
}
