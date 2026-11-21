import SwiftUI

// MARK: - 从模板新建
//
// 模板入口在频道列表右上角，与「空白新建」并列。
// 选中模板后实例化成自己的频道，然后拉起编辑页继续微调。

struct PresetPicker: View {
    @Bindable var store: ChannelStore
    @Binding var isPresented: Bool
    var onCreated: (Channel) -> Void

    @Environment(\.appLocale) private var locale

    var body: some View {
        NavigationStack {
            Group {
                if store.presets.isEmpty {
                    MessageStateView(
                        title: L10n.string("channel.create.empty.title", locale: locale),
                        message: L10n.string("channel.create.empty.message", locale: locale),
                        kind: .empty
                    )
                } else {
                    List {
                        ForEach(store.presets) { preset in
                            Button {
                                Task {
                                    if let created = await store.instantiate(presetID: preset.id) {
                                        isPresented = false
                                        onCreated(created)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text(preset.name)
                                        .font(TypeFace.body(15))
                                        .foregroundStyle(Palette.ink)
                                    if !preset.prompt.isEmpty {
                                        Text(preset.prompt)
                                            .font(TypeFace.footnote)
                                            .foregroundStyle(Palette.inkTertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("preset-picker-\(preset.id)")
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Palette.canvas)
                }
            }
            .sheetContentInset()
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("channel.create.fromPreset", locale: locale))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.done", locale: locale)) {
                        isPresented = false
                    }
                    .font(TypeFace.heading(15))
                    .accessibilityIdentifier("preset-picker-done")
                }
            }
            .task {
                await store.loadCreationOptions()
            }
        }
    }
}
