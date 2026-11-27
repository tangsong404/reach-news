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
                SettingsCard {
                    SettingsRow(
                        title: L10n.string("updates.currentVersion", locale: locale),
                        systemImage: "app.badge",
                        value: version
                    )
                    .settingsCardRow()
                    Divider().padding(.leading, 42)
                    SettingsRow(
                        title: L10n.string("updates.build", locale: locale),
                        systemImage: "number",
                        value: build
                    )
                    .settingsCardRow()

                }
                .settingsCardContainer()
            }
            .listRowBackground(Color.clear)

            Section {
                SettingsCard {
                    Button {
                        showsUnavailable = true
                    } label: {
                        SettingsRow(title: L10n.string("updates.check", locale: locale), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("update-check-button")
                    .buttonStyle(.pressable)
                    .settingsCardRow()
                    if showsUnavailable {
                        Divider()
                        Text(L10n.string("updates.unavailable", locale: locale))
                            .font(typography.body(15))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("update-check-unavailable")
                            .settingsCardRow()
                    }

                }
                .settingsCardContainer()
            }
            .listRowBackground(Color.clear)
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
