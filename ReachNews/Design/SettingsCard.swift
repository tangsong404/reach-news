import SwiftUI

/// Explicit app radius rather than the platform's oversized grouped-list corners.
struct SettingsCard<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .buttonStyle(.pressable)
            .padding(.horizontal, 16)
            .background(Theme.surface(for: env.appearance.style),
                        in: RoundedRectangle(cornerRadius: Radius.medium))
    }
}

extension View {
    /// A whole explicit card occupies one native List row, without a second square surface.
    func settingsCardContainer() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    func settingsCardRow() -> some View {
        padding(.vertical, 10)
    }
}
