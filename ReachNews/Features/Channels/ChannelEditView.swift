import SwiftUI

// MARK: - 频道编辑
//
// 整页一次保存：只提交被改动的字段。运行中 409 busy 时顶部提示且保留全部输入。

struct ChannelEditView: View {
    @AppTypography private var typography

    let channel: Channel
    @Bindable var editor: ChannelEditor
    var onSaved: (Channel) -> Void

    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var showsDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: APIError?
    @State private var showsConnectorPicker = false

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
        // 只有三个一级页面保留标签栏，推入的页面全部隐藏（用户确认）。
        .toolbar(.hidden, for: .tabBar)
            .toolbar { toolbarContent }
            .alert(
                L10n.string("channelEdit.delete.confirm.title", locale: locale),
                isPresented: $showsDeleteConfirm
            ) {
                Button(L10n.string("channelEdit.delete.confirm.action", locale: locale), role: .destructive) {
                    Task { await performDelete() }
                }
                Button(L10n.string("common.cancel", locale: locale), role: .cancel) {}
            } message: {
                Text(L10n.string("channelEdit.delete.confirm.message", locale: locale))
            }
            .sheet(isPresented: $showsConnectorPicker) {
                ConnectorPicker(
                    connectors: env.channels.connectors,
                    selection: $editor.draft.connectorIDs,
                    isPresented: $showsConnectorPicker
                )
                .presentationDetents(SheetMetrics.detents)
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            }
            .task {
                // 记录进入时的颜色，用于判断「只改颜色」也算有改动。
                let stored = env.channelColors.effectiveIndex(for: channel.id)
                editor.initialColorIndex = stored
                editor.currentColorIndex = stored
                if env.channels.connectors.isEmpty {
                    await env.channels.loadCreationOptions()
                }
            }
            .accessibilityIdentifier("channel-edit-view")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if editor.isBlockedByRunning {
                    // 运行中保存：提示原因，已填内容全部保留。
                    InlineNotice(
                        text: L10n.string("channelEdit.busy.title", locale: locale),
                        detail: L10n.string("channelEdit.busy.detail", locale: locale)
                    )
                    .accessibilityIdentifier("channel-edit-busy-notice")
                } else if let error = deleteError {
                    // 删除被拒（如运行中 409）：在顶部提示，保留当前页面。
                    InlineNotice(
                        text: L10n.string(error.messageKey, locale: locale),
                        detail: error.isBusy
                            ? L10n.string("channelEdit.delete.busy", locale: locale)
                            : error.detailText,
                        kind: .error
                    )
                    .accessibilityIdentifier("channel-edit-delete-error")
                } else if let error = editor.saveError {
                    InlineNotice(
                        text: L10n.string(error.messageKey, locale: locale),
                        detail: error.detailText,
                        kind: .error
                    )
                }

                field(titleKey: "channelEdit.name") {
                    FieldBox {
                        TextField("", text: $editor.draft.name)
                            .accessibilityIdentifier("channel-edit-name")
                    }
                }

                // 「频道方向」：多行，给足高度。
                field(titleKey: "channelEdit.prompt") {
                    FieldBox(minHeight: 132) {
                        TextEditor(text: $editor.draft.prompt)
                            .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap()
                            .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
                            .accessibilityIdentifier("channel-edit-prompt")
                    }
                }

                // 口吻：与其它输入框同高，不再显得窄小。
                field(titleKey: "channelEdit.tone") {
                    FieldBox(minHeight: 52) {
                        TextField("", text: $editor.draft.tone, axis: .vertical)
                            .lineLimit(2...4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("channel-edit-tone")
                    }
                }

                field(titleKey: "channelEdit.connectors") {
                    connectorSummary
                }

                field(titleKey: "channelEdit.schedule") {
                    ScheduleEditor(schedule: $editor.draft.schedule)
                }

                field(titleKey: "channelEdit.color") {
                    colorPicker
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            NavTitle(text: L10n.string("channelEdit.title", locale: locale))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(role: .destructive) {
                    showsDeleteConfirm = true
                } label: {
                    Label(L10n.string("channelEdit.delete", locale: locale), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.ink)
            }
            .accessibilityIdentifier("channel-edit-menu")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task {
                    if let updated = await editor.save() {
                        onSaved(updated)
                        dismiss()
                    }
                }
            } label: {
                if editor.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(L10n.string("channelEdit.save", locale: locale))
                        .font(typography.heading(15))
                        .foregroundStyle(editor.hasChanges ? Palette.ink : Palette.inkTertiary)
                }
            }
            .disabled(!editor.hasChanges || editor.isSaving)
            .accessibilityIdentifier("channel-edit-save")
        }
    }

    private func performDelete() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        if await env.channels.delete(channel.id) {
            dismiss()
        } else {
            // 409 表示有运行未结束：提示并保留当前页面。
            deleteError = env.channels.createError
        }
    }

    private var fieldBackground: Color {
        Theme.surface(for: env.appearance.style, mode: env.appearance.mode)
    }

    /// 频道标识色：只在本地保存，不改服务端。
    private var colorPicker: some View {
        ChannelColorRow(
            selection: Binding(
                get: { env.channelColors.effectiveIndex(for: channel.id) },
                set: { newValue in
                    env.channelColors.setColorIndex(newValue, for: channel.id)
                    // 让保存按钮感知到颜色变化。
                    editor.currentColorIndex = newValue
                }
            )
        )
    }

    /// 连接器：一行摘要，点开弹出多选。
    private var connectorSummary: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SelectorRow(
                text: connectorSummaryText,
                isPlaceholder: selectedConnectorNames.isEmpty
            ) {
                showsConnectorPicker = true
            }
            .accessibilityIdentifier("channel-edit-connectors")

            // 仅当原本有连接器、被用户清空时提示；新频道本来就空，不该一进来就报错。
            if editor.draft.connectorIDs.isEmpty && !channel.connectorIDs.isEmpty {
                Text(L10n.string("channelEdit.connectors.emptyWarning", locale: locale))
                    .font(typography.footnote)
                    .foregroundStyle(Palette.failedForeground)
            }
        }
    }

    private var selectedConnectorNames: [String] {
        env.channels.connectors
            .filter { editor.draft.connectorIDs.contains($0.id) }
            .map(\.name)
    }

    private var connectorSummaryText: String {
        let names = selectedConnectorNames
        if names.isEmpty { return L10n.string("channelEdit.connectors.none", locale: locale) }
        if names.count <= 2 { return names.joined(separator: "、") }
        return L10n.format("channelEdit.connectors.someSelected", locale: locale, names.count)
    }

    /// 苹果风格：标题 + 控件，不加解释性小字。
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

// MARK: - 采集时间表编辑

struct ScheduleEditor: View {
    @AppTypography private var typography

    @Binding var schedule: Schedule
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    @State private var showsTimePicker = false
    @State private var draftTime = "08:00"
    @State private var selectedWeekdays: Set<String> = []

    /// 表单里只显示一行摘要，不直接展开滚轮。
    private var summary: String {
        let weekdays = Schedule.weekdays.filter { selectedWeekdays.contains($0.key) }
        guard !weekdays.isEmpty else {
            return L10n.string("schedule.notSet", locale: locale)
        }
        let names = weekdays.map { L10n.string($0.shortKey, locale: locale) }.joined(separator: " ")
        return "\(names)  \(draftTime)"
    }

    var body: some View {
        SelectorRow(text: summary, isPlaceholder: selectedWeekdays.isEmpty) {
            showsTimePicker = true
        }
        .accessibilityIdentifier("schedule-summary")
        .sheet(isPresented: $showsTimePicker) {
            timePickerSheet
        }
        .onAppear(perform: syncFromSchedule)
    }

    /// 闹钟样式：滚轮时间 + 周几选择。
    private var timePickerSheet: some View {
        NavigationStack {
            VStack(spacing: Space.l) {
                DatePicker(
                    "",
                    selection: displayedDate,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("schedule-time-wheel")

                HStack(spacing: Space.xs) {
                    ForEach(Schedule.weekdays) { weekday in
                        let isOn = selectedWeekdays.contains(weekday.key)
                        Button {
                            toggle(weekday)
                        } label: {
                            Text(L10n.string(weekday.shortKey, locale: locale))
                                .font(typography.label(13))
                                .foregroundStyle(isOn ? Palette.canvas : Palette.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Space.s)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                        .fill(isOn ? env.appearance.accent : Theme.surface(for: env.appearance.style, mode: env.appearance.mode))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                        .strokeBorder(Palette.line, lineWidth: isOn ? 0 : 1)
                                }
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("schedule-weekday-\(weekday.key)")
                    }
                }
                .padding(.horizontal, Space.xl)

                Spacer(minLength: 0)
            }
            .padding(.top, Space.l)
            .sheetContentInset()
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("channelEdit.schedule", locale: locale))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.done", locale: locale)) {
                        showsTimePicker = false
                    }
                    .font(typography.heading(15))
                    .accessibilityIdentifier("schedule-picker-done")
                }
            }
        }
        .presentationDetents(SheetMetrics.detents)
    }

    private var displayedDate: Binding<Date> {
        Binding(
            get: { ScheduleDate.parse(draftTime) },
            set: { newValue in
                let formatted = ScheduleDate.format(newValue)
                draftTime = formatted
                applyToSelection(formatted)
            }
        )
    }

    /// 进入时以已配置的第一个时刻与星期为初值。
    private func syncFromSchedule() {
        let existing = schedule.configuredTimes
        draftTime = existing.first ?? "08:00"
        selectedWeekdays = Set(schedule.weekdays(at: draftTime).map(\.key))
    }

    private func toggle(_ weekday: Schedule.Weekday) {
        if selectedWeekdays.contains(weekday.key) {
            selectedWeekdays.remove(weekday.key)
            schedule.removeTime(draftTime, from: weekday)
        } else {
            selectedWeekdays.insert(weekday.key)
            schedule.setTime(draftTime, for: [weekday])
        }
    }

    /// 改时间后，把所有已选星期一起更新成新时刻。
    private func applyToSelection(_ time: String) {
        let weekdays = Schedule.weekdays.filter { selectedWeekdays.contains($0.key) }
        guard !weekdays.isEmpty else { return }
        schedule.setTime(time, for: weekdays)
    }
}

enum ScheduleDate {
    static func parse(_ value: String) -> Date {
        let calendar = Calendar.shanghai
        let parts = value.split(separator: ":").compactMap { Int($0) }
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts.first ?? 8
        components.minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(from: components) ?? Date()
    }

    static func format(_ date: Date) -> String {
        let components = Calendar.shanghai.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 8
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - 连接器名称
//
// 手机端只拿到 connectorId，显示成可读短名；未知 id 原样呈现。

enum ConnectorDisplay {
    static func name(for connectorID: String, locale: Locale) -> String {
        switch connectorID {
        case "cnn_homepage":
            return L10n.string("connector.hn", locale: locale)
        case "cnn_github_trending":
            return L10n.string("connector.githubTrending", locale: locale)
        default:
            return connectorID
        }
    }
}
