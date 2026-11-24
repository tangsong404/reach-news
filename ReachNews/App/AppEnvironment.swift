import SwiftUI
import Observation

// MARK: - 依赖装配
//
// 全部依赖在此创建，视图通过 @Environment 取用；Preview 与 UI 测试注入替身。

@MainActor
@Observable
final class AppEnvironment {
    let session: SessionStore
    let feed: BriefFeedStore
    let channels: ChannelStore
    let saved: SavedStore
    let settings: SettingsStore
    let channelColors: ChannelColorStore
    let preferences: PreferencesStoring
    let profile: ProfileStore

    @ObservationIgnored private let client: APIClient

    init(
        client: APIClient,
        credentials: CredentialProviding,
        preferences: PreferencesStoring,
        savedStorage: SavedBriefsStoring,
        channelColorStorage: ChannelColorStoring
    ) {
        self.client = client
        self.preferences = preferences
        self.feed = BriefFeedStore(client: client, preferences: preferences)
        self.channels = ChannelStore(client: client)
        self.saved = SavedStore(storage: savedStorage)
        self.settings = SettingsStore(client: client)
        self.channelColors = ChannelColorStore(storage: channelColorStorage)
        self.session = SessionStore(
            credentials: credentials,
            preferences: preferences,
            makeClient: { url in client.withBaseURL(url) }
        )
        self.profile = ProfileStore(session: session, preferences: preferences)
    }

    /// 正式运行时的装配。
    static func live() -> AppEnvironment {
        let preferences = UserDefaultsPreferences()
        let credentials = KeychainCredentials()
        let baseURL = BaseURLDefaults.parse(preferences.baseURLString) ?? BaseURLDefaults.url
        let client = APIClient(baseURL: baseURL, credentials: credentials)
        return AppEnvironment(
            client: client,
            credentials: credentials,
            preferences: preferences,
            savedStorage: UserDefaultsSavedBriefs(),
            channelColorStorage: UserDefaultsChannelColors()
        )
    }

    func makeDetailStore(brief: Brief) -> BriefDetailStore {
        BriefDetailStore(brief: brief, client: client)
    }

    func makeAskStore(briefID: String) -> AskStore {
        AskStore(briefID: briefID, client: client)
    }

    func makeChannelEditor(channel: Channel) -> ChannelEditor {
        ChannelEditor(channel: channel, client: client)
    }
}

// MARK: - 环境注入

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}

// MARK: - 语言

private struct AppLocaleKey: EnvironmentKey {
    static let defaultValue: Locale = .autoupdatingCurrent
}

extension EnvironmentValues {
    var appLocale: Locale {
        get { self[AppLocaleKey.self] }
        set { self[AppLocaleKey.self] = newValue }
    }
}
