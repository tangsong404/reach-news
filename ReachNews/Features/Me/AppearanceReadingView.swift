import SwiftUI

/// Inset grouped settings: headings outside cards; consistent icon/title/value columns.
struct AppearanceReadingView: View {
    let preferences: PreferencesStoring
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @AppTypography private var typography

    var body: some View {
        List {
            Section {
                SettingsCard {
                selectionRow("preferences.appearanceMode", symbol: "circle.lefthalf.filled",
                             value: env.appearance.mode.labelKey) {
                    ForEach(AppearanceMode.allCases) { option in
                        Button(L10n.string(option.labelKey, locale: locale)) { env.appearance.select(mode: option) }
                    }
                }
                .accessibilityIdentifier("preferences-appearance-mode")
                .settingsCardRow()
                Divider().padding(.leading, 42)
                selectionRow("preferences.style", symbol: "paintpalette",
                             value: env.appearance.style.labelKey) {
                    ForEach(ReaderStyle.allCases) { option in
                        Button(L10n.string(option.labelKey, locale: locale)) { env.appearance.select(style: option) }
                    }
                }
                .accessibilityIdentifier("preferences-style")
                .settingsCardRow()
                Divider().padding(.leading, 42)
                VStack(spacing: 0) {
                    SettingsRow(title: L10n.string("preferences.textSize", locale: locale),
                                systemImage: "textformat.size",
                                value: "\(Int((env.appearance.textScale * 100).rounded()))%")
                    Slider(value: Binding(
                        get: { env.appearance.textScale },
                        set: { env.appearance.select(textScale: $0) }
                    ), in: 0.90...1.15) {
                        Text(L10n.string("preferences.textSize", locale: locale))
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .accessibilityIdentifier("preferences-text-size-slider")
                    .padding(.bottom, 4)
                }
                Divider().padding(.leading, 42)
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRow(title: L10n.string("preferences.tint.heading", locale: locale), systemImage: "paintbrush.pointed")
                    // Adaptive grid keeps 44pt targets without overflowing small/large-text layouts.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(ThemeTint.allCases) { tint in
                            Button { env.appearance.select(tint: tint) } label: {
                                Circle().fill(tint.color).frame(width: 24, height: 24)
                                    .overlay {
                                        if env.appearance.tint == tint {
                                            Circle().strokeBorder(Palette.ink, lineWidth: 2).padding(-4)
                                        }
                                    }
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel(Text(L10n.string(tint.labelKey, locale: locale)))
                            .accessibilityAddTraits(env.appearance.tint == tint ? [.isSelected] : [])
                            .accessibilityIdentifier("preferences-tint-\(tint.rawValue)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 12)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .all)
                .listRowSeparator(.hidden)
            } header: {
                SettingsSectionHeader(title: L10n.string("preferences.appearance.heading", locale: locale))
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .all)

            Section {
                SettingsCard {
                selectionRow("preferences.language", symbol: "globe", value: language.labelKey) {
                    ForEach(LanguagePreference.allCases) { option in
                        Button(L10n.string(option.labelKey, locale: locale)) { preferences.languagePreference = option.rawValue }
                    }
                }
                .accessibilityIdentifier("preferences-language")
                .settingsCardRow()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .all)
                .listRowSeparator(.hidden)
            } header: {
                SettingsSectionHeader(title: L10n.string("preferences.language.heading", locale: locale))
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .all)

        }
        .settingsListStyle()
        .scrollContentBackground(.hidden)
        .background(Theme.canvas(for: env.appearance.style))
        .navigationTitle(L10n.string("me.preferences", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("appearance-reading")
    }

    private var language: LanguagePreference {
        LanguagePreference(rawValue: preferences.languagePreference) ?? .system
    }

    private func selectionRow<Items: View>(_ title: String, symbol: String, value: String,
                                          @ViewBuilder items: () -> Items) -> some View {
        Menu { items() } label: {
            HStack(spacing: 8) {
                SettingsRow(title: L10n.string(title, locale: locale), systemImage: symbol,
                            value: L10n.string(value, locale: locale))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.inkTertiary)
            }
        }
        .buttonStyle(.pressable)
    }
}
