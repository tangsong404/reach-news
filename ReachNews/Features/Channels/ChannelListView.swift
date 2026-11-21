import SwiftUI

// MARK: - 频道列表
//
// enabled 行上直接切换、失败回滚；运行状态只轮询可见行。

struct ChannelListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @State private var path = NavigationPath()
    @State private var showsCreateSheet = false
    @State private var editingChannel: Channel?
    @State private var showsPresetPicker = false

    var body: some View {
        NavigationStack(path: $path) {
            content(env.channels)
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("tab.channels", locale: locale))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 一个 + 号，菜单里区分「空白新建」与「从模板」。
                    Menu {
                        Button {
                            showsCreateSheet = true
                        } label: {
                            Label(L10n.string("channel.create.blank", locale: locale), systemImage: "square.and.pencil")
                        }
                        Button {
                            showsPresetPicker = true
                        } label: {
                            Label(L10n.string("channel.create.fromPreset", locale: locale), systemImage: "square.on.square")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Palette.ink)
                    }
                    .accessibilityLabel(Text(L10n.string("channel.create.accessibility", locale: locale)))
                    .accessibilityIdentifier("channel-create-button")
                }
            }
            // 必须挂在 NavigationStack 内部，否则点击无反应。
            .navigationDestination(item: $editingChannel) { channel in
                ChannelEditView(
                    channel: channel,
                    editor: env.makeChannelEditor(channel: channel),
                    onSaved: { updated in
                        env.channels.replace(updated)
                    }
                )
            }
            .navigationDestination(isPresented: $showsCreateSheet) {
                ChannelCreateSheet(
                    store: env.channels,
                    isPresented: $showsCreateSheet,
                    onCreated: { channel in
                        env.channels.replace(channel)
                    }
                )
            }
        }
        .task {
            await env.channels.load()
        }
        .onDisappear {
            env.channels.stopPolling()
        }
        .sheet(isPresented: $showsPresetPicker) {
            PresetPicker(store: env.channels, isPresented: $showsPresetPicker) { channel in
                env.channels.replace(channel)
                editingChannel = channel
            }
            .presentationDetents(SheetMetrics.detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.canvas)
        }
    }

    @ViewBuilder
    private func content(_ store: ChannelStore) -> some View {
        VStack(spacing: 0) {
            masthead(store)

            if store.isLoading && store.channels.isEmpty {
                Spacer()
                LoadingLine(text: L10n.string("common.loading", locale: locale))
                Spacer()
            } else if let error = store.error, store.channels.isEmpty {
                Spacer()
                MessageStateView(
                    title: L10n.string(error.messageKey, locale: locale),
                    message: error.isOffline ? L10n.string("error.offline.detail", locale: locale) : error.detailText,
                    kind: .error(error),
                    actionTitle: L10n.string("common.retry", locale: locale),
                    action: { Task { await store.load() } }
                )
                Spacer()
            } else if store.isEmpty {
                Spacer()
                MessageStateView(
                    title: L10n.string("channel.empty.title", locale: locale),
                    message: L10n.string("channel.empty.message", locale: locale),
                    kind: .empty
                )
                Spacer()
            } else {
                list(store)
            }
        }
    }

    /// 只有元信息一行；大标题已由导航栏承担，不重复。
    private func masthead(_ store: ChannelStore) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: Space.s) {
                MetaLine(text: L10n.format("channel.count", locale: locale, store.channels.count))
                DotSeparator()
                MetaLine(
                    text: L10n.format(
                        "channel.timezoneNote",
                        locale: locale,
                        env.settings.displayTimeZone
                    )
                )
            }
            if let error = store.error, !store.channels.isEmpty {
                InlineNotice(text: L10n.string(error.messageKey, locale: locale))
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.m)
    }

    private func list(_ store: ChannelStore) -> some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                ForEach(store.channels) { channel in
                    Button {
                        editingChannel = channel
                    } label: {
                        ChannelCard(
                            channel: channel,
                            run: store.latestRun(for: channel.id),
                            isPending: store.pendingChannelIDs.contains(channel.id),
                            colorIndex: env.channelColors.colorIndex(for: channel.id),
                            onToggle: { enabled in
                                Task { await store.setEnabled(enabled, for: channel.id) }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        store.updateVisibleChannels(store.visibleChannelIDs.union([channel.id]))
                        store.startPolling()
                    }
                    .onDisappear {
                        var visible = store.visibleChannelIDs
                        visible.remove(channel.id)
                        store.updateVisibleChannels(visible)
                        if visible.isEmpty {
                            store.stopPolling()
                        }
                    }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, 96)
        }
        .refreshable {
            await store.load()
        }
        .accessibilityIdentifier("channel-list")
    }
}

// MARK: - 频道卡

struct ChannelCard: View {
    let channel: Channel
    let run: Run?
    let isPending: Bool
    var colorIndex: Int?
    var onToggle: (Bool) -> Void

    @Environment(\.appLocale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                ChannelDot(channelID: channel.id, diameter: 8, colorIndex: colorIndex)
                Text(channel.name)
                    .font(TypeFace.heading(15))
                    .foregroundStyle(Palette.ink)
                if channel.kind == .follow {
                    Text(L10n.string("channel.kind.follow", locale: locale))
                        .font(TypeFace.condensed(9.5, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Palette.lineStrong, lineWidth: 1)
                        }
                }
                Spacer(minLength: 0)
                ChannelToggle(isOn: channel.enabled, isPending: isPending, action: onToggle)
            }

            if !channel.prompt.isEmpty {
                Text(channel.prompt)
                    .font(TypeFace.body(12.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }

            HStack(spacing: Space.s) {
                if let status = statusChip {
                    status
                }
                if let scheduleText {
                    Text(scheduleText)
                        .font(TypeFace.condensed(11, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 11)

            // 连接器名称直接来自服务端，不再显示 UUID。
            if !channel.connectors.isEmpty {
                HStack(spacing: Space.xs) {
                    ForEach(channel.connectors) { connector in
                        Text(connector.displayName)
                            .font(TypeFace.condensed(10.5, weight: .medium))
                            .foregroundStyle(connector.isUnavailable ? Palette.failedForeground : Palette.inkTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, Space.xs)
                .accessibilityIdentifier("channel-connectors-\(channel.id)")
            }

            // 频道已启用但没有连接器：运行必然错过（no-material）。
            if channel.warnsAboutMissingConnectors {
                InlineNotice(text: L10n.string("channel.noConnectors", locale: locale))
                    .padding(.top, Space.s)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("channel-card-\(channel.id)")
    }

    /// 运行状态三分法：进行中绿、错过中性灰、失败警示色。
    private var statusChip: StatusChip? {
        guard channel.enabled else {
            return StatusChip(style: .neutral, text: L10n.string("channel.state.disabled", locale: locale))
        }
        guard let run else { return nil }
        switch run.state {
        case .queued, .collecting, .writing:
            return StatusChip(style: .running, text: L10n.string("channel.state.running", locale: locale))
        case .missed:
            return StatusChip(style: .missed, text: L10n.string("channel.state.missed", locale: locale))
        case .failed:
            return StatusChip(style: .failed, text: L10n.string("channel.state.failed", locale: locale))
        case .published, .cancelled:
            return nil
        }
    }

    /// 「周一、三、五 08:00」「每天 07:30」「每周二 09:00」
    private var scheduleText: String? {
        ScheduleDisplay.summary(channel.schedule, locale: locale)
    }
}

// MARK: - 时间表描述

enum ScheduleDisplay {
    static func summary(_ schedule: Schedule, locale: Locale) -> String? {
        let active = schedule.activeWeekdays
        guard !active.isEmpty else { return nil }

        let times = schedule.allTimes
        let timeText = times.count == 1 ? times[0] : times.joined(separator: " / ")
        let allWeekdays = active.count == Schedule.weekdays.count

        if allWeekdays {
            return L10n.format("schedule.everyDay", locale: locale, timeText)
        }
        if active.count == 1, let first = active.first {
            let label = L10n.string(first.symbolKey, locale: locale)
            return L10n.format("schedule.singleWeekday", locale: locale, label, timeText)
        }
        let names = active.map { L10n.string($0.symbolKey, locale: locale) }
        return L10n.format("schedule.multiWeekday", locale: locale, names.joined(separator: "、"), timeText)
    }
}
