import SwiftUI

// MARK: - 连接器选择
//
// 不在表单里平铺一长串开关，改为独立的多选列表。

struct ConnectorPicker: View {
    @AppTypography private var typography

    let connectors: [Connector]
    @Binding var selection: [String]
    @Binding var isPresented: Bool

    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            List {
                ForEach(connectors) { connector in
                    Button {
                        toggle(connector.id)
                    } label: {
                        HStack {
                            Text(connector.name)
                                .font(typography.body(15))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            if selection.contains(connector.id) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("connector-picker-\(connector.id)")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            .sheetContentInset()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("channelEdit.connectors", locale: locale))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.done", locale: locale)) {
                        isPresented = false
                    }
                    .font(typography.heading(14))
                    .accessibilityIdentifier("connector-picker-done")
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }
}
