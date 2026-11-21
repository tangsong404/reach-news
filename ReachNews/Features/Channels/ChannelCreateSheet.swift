import SwiftUI

// MARK: - 新建频道
//
// 后端已提供 POST /api/v1/channels，不再需要预设才能建。
// 连接器必选：空连接器的频道启用后每次运行都会 missed。
// 预设仍可作为「填入模板」的快捷方式。

struct ChannelCreateSheet: View {
    @Bindable var store: ChannelStore
    @Binding var isPresented: Bool
    var onCreated: (Channel) -> Void

    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""
    @State private var tone = ""
    @State private var schedule = Schedule()
    @State private var selectedConnectorIDs: Set<String> = []
    @State private var showsConnectorPicker = false
    @State private var selectedColorIndex: Int = 0
    @State private var showConnectorValidation = false

    /// 只校验必填文本；连接器缺失在提交时提示，不提前禁用按钮。
    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
            && !store.isCreating
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = store.createError {
                        InlineNotice(
                            text: L10n.string(error.messageKey, locale: locale),
                            detail: error.detailText,
                            kind: .error
                        )
                    }

                    field(titleKey: "channelEdit.name") {
                        FieldBox {
                            TextField("", text: $name)
                                .accessibilityIdentifier("channel-create-name")
                        }
                    }

                    field(titleKey: "channelEdit.prompt") {
                        FieldBox(minHeight: 132) {
                            TextEditor(text: $prompt)
                                .scrollContentBackground(.hidden)
                                .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
                                .accessibilityIdentifier("channel-create-prompt")
                        }
                    }

                    field(titleKey: "channelEdit.tone") {
                        FieldBox(minHeight: 52) {
                            TextField("", text: $tone, axis: .vertical)
                                .lineLimit(2...4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("channel-create-tone")
                        }
                    }

                    field(titleKey: "channelEdit.connectors") {
                        connectorSummary
                    }

                    field(titleKey: "channelEdit.schedule") {
                        ScheduleEditor(schedule: $schedule)
                    }

                    // 新建时一并选色，避免先用回退色再进编辑页调整。
                    field(titleKey: "channelEdit.color") {
                        colorPicker
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxl)
            }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("channel.create.title", locale: locale))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if store.isCreating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.string("channel.create.submit", locale: locale))
                                .font(TypeFace.heading(14))
                                .foregroundStyle(canSubmit ? Palette.ink : Palette.inkTertiary)
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("channel-create-submit")
                }
            }
        .sheet(isPresented: $showsConnectorPicker) {
            ConnectorPicker(
                connectors: store.connectors,
                selection: Binding(
                    get: { Array(selectedConnectorIDs) },
                    set: { selectedConnectorIDs = Set($0) }
                ),
                isPresented: $showsConnectorPicker
            )
            .presentationDetents(SheetMetrics.detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.canvas)
        }
        .task {
            await store.loadCreationOptions()
            // 默认挑一个当前用得最少的颜色。
            selectedColorIndex = env.channelColors.suggestedIndex()
        }
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("channel-create-sheet")
    }

    private func submit() async {
        guard !store.isCreating else { return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // 连接器为空时提示，而不是从一进页面就报错。
        guard !selectedConnectorIDs.isEmpty else {
            showConnectorValidation = true
            return
        }
        if let created = await store.create(
            name: name.trimmingCharacters(in: .whitespaces),
            prompt: prompt.trimmingCharacters(in: .whitespaces),
            tone: tone,
            schedule: schedule,
            connectorIDs: Array(selectedConnectorIDs)
        ) {
            env.channelColors.setColorIndex(selectedColorIndex, for: created.id)
            onCreated(created)
            // 作为导航页时用 dismiss 回退，而不是翻转 sheet 绑定。
            isPresented = false
            dismiss()
        }
    }

    /// 连接器：一行摘要，点开弹出多选。
    /// 新建时的颜色选择；默认选中一个还没用过的颜色。
    private var colorPicker: some View {
        ChannelColorRow(selection: $selectedColorIndex)
    }

    private var connectorSummary: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SelectorRow(
                text: summaryText,
                isPlaceholder: selectedConnectorIDs.isEmpty
            ) {
                showsConnectorPicker = true
            }
            .accessibilityIdentifier("channel-create-connectors")

            // 用户还没提交时不报错；只有点了创建仍为空才提示。
            if showConnectorValidation && selectedConnectorIDs.isEmpty {
                Text(L10n.string("channelEdit.connectors.emptyWarning", locale: locale))
                    .font(TypeFace.footnote)
                    .foregroundStyle(Palette.failedForeground)
            }
        }
    }

    private var summaryText: String {
        let names = store.connectors
            .filter { selectedConnectorIDs.contains($0.id) }
            .map(\.name)
        if names.isEmpty { return L10n.string("channelEdit.connectors.none", locale: locale) }
        if names.count <= 2 { return names.joined(separator: "、") }
        return L10n.format("channelEdit.connectors.someSelected", locale: locale, names.count)
    }

    private func field<Content: View>(
        titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(L10n.string(titleKey, locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            content()
        }
    }
}
