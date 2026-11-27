import SwiftUI

struct HelpAboutView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    private enum HelpDestination: Hashable { case updates }

    var body: some View {
        List {
            Section {
                NavigationLink(value: HelpDestination.updates) {
                    SettingsRow(title: L10n.string("updates.title", locale: locale), systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("help-check-updates")
            }
            .listRowBackground(Theme.surface(for: env.appearance.style))
        }
        .settingsListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.canvas(for: env.appearance.style))
        .navigationTitle(L10n.string("me.help", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("help-about")
        .navigationDestination(for: HelpDestination.self) { destination in
            switch destination {
            case .updates: UpdateCheckView()
            }
        }
    }
}
