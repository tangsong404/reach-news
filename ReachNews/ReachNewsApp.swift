import SwiftUI

@main
struct ReachNewsApp: App {
    @State private var environment = AppEnvironment.live()
    @AppStorage("preferences.language") private var languagePreference = LanguagePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .environment(\.appEnvironment, environment)
                .environment(\.appLocale, appLocale)
                .tint(environment.appearance.accent)
                // 稿子只有纸色外观。
                .preferredColorScheme(.light)
        }
    }

    private var appLocale: Locale {
        (LanguagePreference(rawValue: languagePreference) ?? .system).locale
    }
}
