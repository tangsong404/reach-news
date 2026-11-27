import SwiftUI

/// Shared settings row: a fixed icon column, readable title, and optional value.
/// The value moves below the title at accessibility sizes rather than clipping.
struct SettingsRow: View {
    @AppTypography private var typography
    let title: String
    let systemImage: String
    var value: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    if let value, !value.isEmpty { valueText(value) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    titleText
                    Spacer(minLength: 8)
                    if let value, !value.isEmpty { valueText(value) }
                }
            }
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { _ in 42 }
    }

    private var titleText: some View {
        Text(title)
            .font(typography.body(17))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(typography.body(15))
            .foregroundStyle(Palette.inkSecondary)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Group title belongs outside the card, with native inset-grouped alignment.
struct SettingsSectionHeader: View {
    @AppTypography private var typography
    let title: String
    var body: some View {
        Text(title)
            .font(typography.body(15))
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsListStyle: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    func body(content: Content) -> some View {
        content
            .listStyle(.grouped)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 52)
            .listSectionSpacing(12)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .font(.body)
            .fontDesign(.default)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
    }
}

extension View {
    func settingsListStyle() -> some View { modifier(SettingsListStyle()) }
}
