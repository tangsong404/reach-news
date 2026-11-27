import SwiftUI

struct HelpAboutView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @AppTypography private var typography

    var body: some View {
        List {
            Section {
                Text(L10n.string("me.help.placeholder", locale: locale))
                    .font(typography.body(17))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } header: {
                SettingsSectionHeader(title: L10n.string("me.help", locale: locale))
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
    }
}
