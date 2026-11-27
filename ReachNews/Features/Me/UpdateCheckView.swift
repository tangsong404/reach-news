import SwiftUI

/// Update discovery stays explicitly unavailable until a real backend contract exists.
/// Current version values come from the installed app, never a fabricated latest release.
struct UpdateCheckView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @AppTypography private var typography
    @State private var showsUnavailable = false

    var body: some View {
        List {
            Section {
                SettingsRow(
                    title: L10n.string("updates.currentVersion", locale: locale),
                    systemImage: "app.badge",
                    value: version
                )
                SettingsRow(
                    title: L10n.string("updates.build", locale: locale),
                    systemImage: "number",
                    value: build
                )
            }
            .listRowBackground(Theme.surface(for: env.appearance.style))

            Section {
                Button {
                    showsUnavailable = true
                } label: {
                    SettingsRow(title: L10n.string("updates.check", locale: locale), systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("update-check-button")
                if showsUnavailable {
                    Text(L10n.string("updates.unavailable", locale: locale))
                        .font(typography.body(15))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("update-check-unavailable")
                }
            }
            .listRowBackground(Theme.surface(for: env.appearance.style))
        }
        .settingsListStyle()
        .navigationTitle(L10n.string("updates.title", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("update-check-page")
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
