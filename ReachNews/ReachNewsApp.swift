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
    /// 读取字号设置：它变化时整棵树会重算，`TypeFace` 才能取到新的缩放值。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .environment(\.appEnvironment, environment)
                .environment(\.appLocale, appLocale)
                .tint(environment.appearance.accent)
                .fontDesign(environment.appearance.style == .editorial ? .serif : .default)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                // 稿子只有纸色外观。
                .preferredColorScheme(environment.appearance.resolvedColorScheme)
        }
    }

    private var appLocale: Locale {
        (LanguagePreference(rawValue: languagePreference) ?? .system).locale
    }
}
