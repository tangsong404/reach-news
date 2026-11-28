import SwiftUI

// MARK: - 新建频道
//
// New channels bind approved collector Skill IDs, never historical connector IDs.
// A disabled draft may be saved with no source; enabling is always an explicit user choice.
// 预设模板已整体下线（订阅是关系，不是类型），新建只有「空白新建」一条路径。

struct ChannelCreateSheet: View {
    @AppTypography private var typography

    @Bindable var store: ChannelStore
    @Binding var isPresented: Bool
    var onCreated: (Channel) -> Void
    /// 从日报正文的「跟踪事件」进入时的标题；为 nil 时是普通新建。
    /// 事件不是新的后端实体：只是把名称与提示词预填好，仍按普通频道提交。
    var eventHeading: String?

    init(
        store: ChannelStore,
        isPresented: Binding<Bool>,
        onCreated: @escaping (Channel) -> Void,
        eventHeading: String? = nil
    ) {
        self.store = store
        self._isPresented = isPresented
        self.onCreated = onCreated
        self.eventHeading = eventHeading
    }

    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""
    @State private var tone = ""
    @State private var schedule = Schedule()
    @State private var selectedCollectorSkillIDs: Set<String> = []
    @State private var showsCollectorPicker = false
    @State private var selectedColorIndex: Int = 0
    @State private var showCollectorValidation = false
    @State private var enabled = false

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
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap()
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

                    Toggle(L10n.string("collector.enable", locale: locale), isOn: $enabled)
                        .font(typography.body(15))
                        .accessibilityIdentifier("channel-create-enabled")

                    field(titleKey: "collector.sources") {
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
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
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
                                .font(typography.heading(14))
                                .foregroundStyle(canSubmit ? Palette.ink : Palette.inkTertiary)
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("channel-create-submit")
                }
            }
        .sheet(isPresented: $showsCollectorPicker) {
            CollectorSkillPicker(
                skills: store.collectorSkills,
                selection: Binding(
                    get: { Array(selectedCollectorSkillIDs) },
                    set: { selectedCollectorSkillIDs = Set($0) }
                ),
                isPresented: $showsCollectorPicker
            )
            .presentationDetents(SheetMetrics.detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        }
        .task {
            await store.loadCreationOptions()
            // 默认挑一个当前用得最少的颜色。
            selectedColorIndex = env.channelColors.suggestedIndex()
            applyEventDraftIfNeeded()
        }
        .accessibilityIdentifier("channel-create-sheet")
    }

    /// 事件模式：只在小标题进来时预填一次名称与提示词，之后完全交给用户修改。
    /// 普通新建时 eventHeading 为 nil，什么都不做。
    private func applyEventDraftIfNeeded() {
        guard let eventHeading, name.isEmpty, prompt.isEmpty else { return }
        name = TrackedEventDraft.name(heading: eventHeading)
        prompt = TrackedEventDraft.prompt(heading: eventHeading, locale: locale)
    }

    private func submit() async {
        guard !store.isCreating else { return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // 连接器为空时提示，而不是从一进页面就报错。
        guard !enabled || hasAvailableSelection else {
            showCollectorValidation = true
            return
        }
        if let created = await store.create(
            name: name.trimmingCharacters(in: .whitespaces),
            prompt: prompt.trimmingCharacters(in: .whitespaces),
            tone: tone,
            schedule: schedule,
            collectorSkillIDs: Array(selectedCollectorSkillIDs),
            enabled: enabled
        ) {
            env.channelColors.setColorIndex(selectedColorIndex, for: created.id)
            onCreated(created)
            // 作为导航页时用 dismiss 回退，而不是翻转 sheet 绑定。
            isPresented = false
            dismiss()
        }
    }

    /// 新建时的颜色选择；默认选中一个还没用过的颜色。
    private var colorPicker: some View {
        ChannelColorRow(selection: $selectedColorIndex)
    }

    private var connectorSummary: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SelectorRow(
                text: summaryText,
                isPlaceholder: selectedCollectorSkillIDs.isEmpty
            ) {
                showsCollectorPicker = true
            }
            .accessibilityIdentifier("channel-create-connectors")

            // 用户还没提交时不报错；只有点了创建仍为空才提示。
            if showCollectorValidation && enabled && !hasAvailableSelection {
                Text(L10n.string("collector.required", locale: locale))
                    .font(typography.footnote)
                    .foregroundStyle(Palette.failedForeground)
            }
        }
    }

    private var hasAvailableSelection: Bool {
        !selectedCollectorSkillIDs.isEmpty && selectedCollectorSkillIDs.allSatisfy { id in
            store.collectorSkills.contains { $0.id == id && $0.available }
        }
    }

    private var summaryText: String {
        let names = store.collectorSkills
            .filter { selectedCollectorSkillIDs.contains($0.id) }
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
                .font(typography.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            content()
        }
    }
}
