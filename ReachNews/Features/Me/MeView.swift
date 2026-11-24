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
                case .connection:
                    ConnectionInfoView(session: env.session)
                }
            }
        }
    }

    private func content(_ env: AppEnvironment) -> some View {
        List {
            AccountHeaderView(profile: env.profile)
                .listRowBackground(Palette.surface)

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

                NavigationLink(value: MeDestination.connection) {
                    Label {
                        Text(L10n.string("me.connection", locale: locale))
                    } icon: {
                        Image(systemName: "link")
                    }
                }
                .accessibilityIdentifier("me-connection")
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
    case connection
}

// MARK: - 收藏列表

struct SavedBriefsView: View {
    let store: BriefFeedStore
    let saved: SavedStore
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    private var savedBriefs: [Brief] {
        store.briefs
            .filter { saved.savedIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if savedBriefs.isEmpty {
                MessageStateView(
                    title: L10n.string("me.saved.empty.title", locale: locale),
                    message: L10n.string("me.saved.empty.message", locale: locale),
                    kind: .empty
                )
            } else {
                List {
                    ForEach(savedBriefs) { brief in
                        NavigationLink(value: brief) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(brief.title)
                                    .font(TypeFace.heading(14.5))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                HStack(spacing: 7) {
                                    ChannelDot(channelID: brief.channelID, colorIndex: env.channelColors.colorIndex(for: brief.channelID))
                                    Text(store.displayName(for: brief))
                                        .font(TypeFace.label(11))
                                        .foregroundStyle(Palette.inkSecondary)
                                    DotSeparator()
                                    MetaLine(text: DisplayTime.monthDayTime(brief.createdAt, locale: locale))
                                }
                            }
                            .padding(.vertical, Space.xxs)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                saved.toggle(brief.id)
                            } label: {
                                Label(L10n.string("me.saved.remove", locale: locale), systemImage: "bookmark.slash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Palette.canvas)
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
        .accessibilityIdentifier("saved-list")
    }
}

// MARK: - 偏好

struct PreferencesView: View {
    let session: SessionStore
    let preferences: PreferencesStoring
    @Environment(\.appLocale) private var locale
    @State private var baseURLString: String = ""

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

            Section {
                TextField(L10n.string("connection.baseURL.placeholder", locale: locale), text: $baseURLString)
                    .font(TypeFace.body(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("preferences-baseurl")

                Button {
                    saveBaseURL()
                } label: {
                    Text(L10n.string("preferences.baseURL.save", locale: locale))
                        .font(TypeFace.heading(13.5))
                        .foregroundStyle(hasValidChange ? Palette.ink : Palette.inkTertiary)
                }
                .disabled(!hasValidChange)
                .accessibilityIdentifier("preferences-baseurl-save")
            } header: {
                Text(L10n.string("preferences.baseURL.heading", locale: locale))
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
        .onAppear {
            baseURLString = preferences.baseURLString
        }
    }

    private var hasValidChange: Bool {
        guard let url = BaseURLDefaults.parse(baseURLString) else { return false }
        return url.absoluteString != preferences.baseURLString
    }

    private func saveBaseURL() {
        guard let url = BaseURLDefaults.parse(baseURLString) else { return }
        preferences.baseURLString = url.absoluteString
        baseURLString = url.absoluteString
    }
}

// MARK: - 连接信息

struct ConnectionInfoView: View {
    let session: SessionStore
    @Environment(\.appLocale) private var locale

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L10n.string("connection.currentAddress", locale: locale))
                        .font(TypeFace.body(13))
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer(minLength: Space.s)
                    Text(session.baseURLString)
                        .font(TypeFace.condensed(12.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                HStack {
                    Text(L10n.string("connection.credential", locale: locale))
                        .font(TypeFace.body(13))
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer(minLength: Space.s)
                    Text(L10n.string(session.credentialSummaryKey, locale: locale))
                        .font(TypeFace.label(12.5))
                        .foregroundStyle(session.isSignedIn ? Palette.runningForeground : Palette.inkTertiary)
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                if let expires = session.expiresAt {
                    HStack {
                        Text(L10n.string("connection.expires", locale: locale))
                            .font(TypeFace.body(13))
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer(minLength: Space.s)
                        Text(DisplayTime.monthDayTime(expires, locale: locale))
                            .font(TypeFace.condensed(12.5, weight: .medium))
                            .foregroundStyle(Palette.ink)
                    }
                }

                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Text(L10n.string("connection.signOut", locale: locale))
                        .font(TypeFace.body(13.5))
                }
                .accessibilityIdentifier("connection-signout")
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("me.connection", locale: locale))
            }
        }
        .accessibilityIdentifier("connection-info")
    }
}
