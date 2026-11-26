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
                .fontDesign(environment.appearance.style == .editorial ? .serif : .default)
                // 稿子只有纸色外观。
                .preferredColorScheme(environment.appearance.resolvedColorScheme)
        }
    }

    private var appLocale: Locale {
        (LanguagePreference(rawValue: languagePreference) ?? .system).locale
    }
}
