import SwiftUI

// MARK: - 我的
//
// 收藏（仅本机）+ 偏好 + 连接信息。

struct MeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale

    var body: some View {
        NavigationStack {
            content(env)
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("tab.me", locale: locale))
                }
            }
            .navigationDestination(for: MeDestination.self) { destination in
                switch destination {
                case .saved:
                    SavedBriefsView(store: env.feed, saved: env.saved)
                case .preferences:
                    PreferencesView(session: env.session, preferences: env.preferences)
                case .account:
                    AccountDetailView(session: env.session)
                }
            }
        }
    }

    private func content(_ env: AppEnvironment) -> some View {
        List {
            // 整张账号卡片点进个人页；连接信息不再单列入口。
            NavigationLink(value: MeDestination.account) {
                AccountHeaderView(profile: env.profile)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l, bottom: Space.s, trailing: Space.l))
            .listRowBackground(Palette.surface)
            .accessibilityIdentifier("me-account-card")

            Section {
                NavigationLink(value: MeDestination.saved) {
                    Label {
                        Text(L10n.string("me.saved", locale: locale))
                    } icon: {
                        Image(systemName: "bookmark")
                    }
                    .badge(env.saved.savedIDs.count)
                }
                .accessibilityIdentifier("me-saved")

                NavigationLink(value: MeDestination.preferences) {
                    Label {
                        Text(L10n.string("me.preferences", locale: locale))
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                .accessibilityIdentifier("me-preferences")

            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .accessibilityIdentifier("me-list")
    }
}

enum MeDestination: Hashable {
    case saved
    case preferences
    /// 账号卡片点进去的个人页：资料、头像、密码与退出登录都在这里。
    case account
}

// MARK: - 收藏列表
//
// 数据来自 `SavedFeedStore`：按 ID 逐条拉取，不依赖首页已加载内容。
// 因此无论列表翻到哪一页、或重进 App，收藏都不会消失。

struct SavedBriefsView: View {
    let saved: SavedStore
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
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("me.saved", locale: locale))
            }
        }
        .navigationDestination(for: Brief.self) { brief in
            BriefDetailView(brief: brief, store: env.makeDetailStore(brief: brief))
        }
        .task {
            await env.savedFeed.load(ids: savedIDs)
        }
        .accessibilityIdentifier("saved-list")
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
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
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
                    .font(TypeFace.body(12))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 0)
                Button {
                    Task { await env.savedFeed.retry(id: id) }
                } label: {
                    Text(L10n.string("common.retry", locale: locale))
                        .font(TypeFace.label(12))
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().controlSize(.small)
                Text(L10n.string("common.loading", locale: locale))
                    .font(TypeFace.body(12))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    private func row(for brief: Brief) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(brief.title)
                .font(TypeFace.heading(14.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            if let summary = brief.displaySummary {
                Text(summary)
                    .font(TypeFace.body(12.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 7) {
                ChannelDot(channelID: brief.channelID, colorIndex: env.channelColors.colorIndex(for: brief.channelID))
                Text(brief.channelName ?? "")
                    .font(TypeFace.label(11))
                    .foregroundStyle(Palette.inkSecondary)
                DotSeparator()
                MetaLine(text: DisplayTime.monthDayTime(brief.createdAt, locale: locale))
            }
        }
        .padding(.vertical, Space.xxs)
    }
}

// MARK: - 偏好

struct PreferencesView: View {
    let session: SessionStore
    let preferences: PreferencesStoring
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                Picker(selection: Binding(
                    get: { LanguagePreference(rawValue: preferences.languagePreference) ?? .system },
                    set: { preferences.languagePreference = $0.rawValue }
                )) {
                    ForEach(LanguagePreference.allCases) { option in
                        Text(L10n.string(option.labelKey, locale: locale))
                            .tag(option)
                    }
                } label: {
                    Text(L10n.string("preferences.language", locale: locale))
                }
                .accessibilityIdentifier("preferences-language")
            } header: {
                Text(L10n.string("preferences.language.heading", locale: locale))
            }
            .listRowBackground(Palette.surface)

            // 风格：两套观感，只改基调不改结构。
            Section {
                Picker(selection: Binding(
                    get: { env.appearance.style },
                    set: { env.appearance.select(style: $0) }
                )) {
                    ForEach(ReaderStyle.allCases) { option in
                        Text(L10n.string(option.labelKey, locale: locale))
                            .tag(option)
                    }
                } label: {
                    Text(L10n.string("preferences.style", locale: locale))
                }
                .accessibilityIdentifier("preferences-style")
            } header: {
                Text(L10n.string("preferences.style.heading", locale: locale))
            }
            .listRowBackground(Palette.surface)

            // 主题色：一行色点，点选即生效。
            Section {
                tintRow
            } header: {
                Text(L10n.string("preferences.tint.heading", locale: locale))
            }
            .listRowBackground(Palette.surface)

        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("me.preferences", locale: locale))
            }
        }
    }

    /// 主题色：横向色点，选中项带外圈。
    private var tintRow: some View {
        HStack(spacing: Space.m) {
            ForEach(ThemeTint.allCases) { option in
                Button {
                    env.appearance.select(tint: option)
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .strokeBorder(Palette.ink, lineWidth: env.appearance.tint == option ? 2 : 0)
                                .padding(-4)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.string(option.labelKey, locale: locale)))
                .accessibilityIdentifier("preferences-tint-\(option.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xxs)
    }
}
