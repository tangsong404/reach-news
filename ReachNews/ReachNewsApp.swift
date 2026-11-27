import SwiftUI

@main
struct ReachNewsApp: App {
    @State private var environment: AppEnvironment = {
        #if DEBUG
        if UITestLaunchFixture.isEnabled { return UITestLaunchFixture.makeEnvironment() }
        #endif
        return AppEnvironment.live()
    }()
    @AppStorage("preferences.language") private var languagePreference = LanguagePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .environment(\.appEnvironment, environment)
                .environment(\.appLocale, appLocale)
                .tint(environment.appearance.accent)
                .fontDesign(.default)
                .readingTypography(textSize: environment.appearance.textSize)
                // 稿子只有纸色外观。
                .preferredColorScheme(environment.appearance.resolvedColorScheme)
        }
    }

    private var appLocale: Locale {
        (LanguagePreference(rawValue: languagePreference) ?? .system).locale
    }
}
