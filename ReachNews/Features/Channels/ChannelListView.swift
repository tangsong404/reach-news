import SwiftUI

// MARK: - 频道列表
//
// 三段式单页：我的频道 → 订阅的频道 → 发现更多。
// 可写性一律看 owner：订阅卡只读，「发现更多」只用「订阅」一个动作。
// enabled 行上直接切换、失败回滚；运行状态只轮询可见行。

struct ChannelListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @State private var path = NavigationPath()
    @State private var showsCreateSheet = false

    /// 同一个 NavigationStack 里有两种目的地，用枚举区分，避免同类型 item 互相覆盖。
    enum Route: Hashable {
        case edit(Channel)
        case subscribed(Channel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content(env.channels)
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("tab.channels", locale: locale))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if env.session.capabilities.channelLimit == nil ||
                        env.channels.myChannels.count < (env.session.capabilities.channelLimit ?? 0) {
                        Button {
                            showsCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Palette.ink)
                        }
                        .accessibilityLabel(Text(L10n.string("channel.create.accessibility", locale: locale)))
                        .accessibilityIdentifier("channel-create-button")
                    }
                }
            }
            // 必须挂在 NavigationStack 内部，否则点击无反应。
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .edit(let channel):
                    ChannelEditView(
                        channel: channel,
                        editor: env.makeChannelEditor(channel: channel),
                        onSaved: { updated in
                            env.channels.replace(updated)
                        }
                    )
                case .subscribed(let channel):
                    SubscribedChannelDetail(
                        channel: channel,
                        onUpdated: { updated in
                            // 详情页自己持有最新快照；这里只同步列表。
                            env.channels.replace(updated)
                        },
                        onForked: { created in
                            env.channels.replace(created)
                            // fork 会取消原订阅：原频道的日报同样立即不可见。
                            env.feed.forgetChannel(channel.id)
                            // 先退出只读页，再进入新频道的编辑页，避免两页叠在一起。
                            path = NavigationPath()
                            path.append(Route.edit(created))
                        },
                        onUnsubscribed: {
                            // 服务端立即对所有读取路径隐藏该频道，本地日报流同步清掉。
                            env.feed.forgetChannel(channel.id)
                            path = NavigationPath()
                        }
                    )
                }
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
    }

    @ViewBuilder
    private func content(_ store: ChannelStore) -> some View {
        VStack(spacing: 0) {
            masthead(store)

            if store.isLoading && store.myChannels.isEmpty && store.subscribedChannels.isEmpty {
                Spacer()
                LoadingLine(text: L10n.string("common.loading", locale: locale))
                Spacer()
            } else if let error = store.error, store.myChannels.isEmpty, store.subscribedChannels.isEmpty {
                Spacer()
                MessageStateView(
                    title: L10n.string(error.messageKey, locale: locale),
                    message: error.isOffline ? L10n.string("error.offline.detail", locale: locale) : error.detailText,
                    kind: .error(error),
                    actionTitle: L10n.string("common.retry", locale: locale),
                    action: { Task { await store.load() } }
                )
                Spacer()
            } else if store.isFullyEmpty {
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
                if !store.myChannels.isEmpty {
                    sectionHeader("channel.section.mine")
                    ForEach(store.myChannels) { channel in
                        Button {
                            path.append(Route.edit(channel))
                        } label: {
                            ChannelCard(
                                channel: channel,
                                run: store.latestRun(for: channel.id),
                                isPending: store.pendingChannelIDs.contains(channel.id),
                                colorIndex: env.channelColors.displayIndex(for: channel),
                                onToggle: { enabled in
                                    Task { await store.setEnabled(enabled, for: channel.id) }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear { track(channel, store: store) }
                        .onDisappear { untrack(channel, store: store) }
                    }
                }

                if !store.subscribedChannels.isEmpty {
                    sectionHeader("channel.section.subscribed")
                    ForEach(store.subscribedChannels) { channel in
                        Button {
                            path.append(Route.subscribed(channel))
                        } label: {
                            SubscribedChannelCard(
                                channel: channel,
                                run: store.latestRun(for: channel.id),
                                colorIndex: env.channelColors.displayIndex(for: channel)
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear { track(channel, store: store) }
                        .onDisappear { untrack(channel, store: store) }
                    }
                }

                discoverSection(store)
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

    // MARK: 发现更多

    @ViewBuilder
    private func discoverSection(_ store: ChannelStore) -> some View {
        VStack(spacing: Space.m) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.isDiscoverExpanded.toggle()
                }
                if store.isDiscoverExpanded && store.discoverableChannels.isEmpty {
                    Task { await store.loadDiscoverable() }
                }
            } label: {
                HStack(spacing: Space.s) {
                    Text(L10n.string("channel.section.discover", locale: locale))
                        .font(TypeFace.label(11))
                        .tracking(1)
                        .foregroundStyle(Palette.inkTertiary)
                    if !store.discoverableChannels.isEmpty {
                        Text("\(store.discoverableChannels.count)")
                            .font(TypeFace.condensed(10.5, weight: .semibold))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Rectangle()
                        .fill(Palette.line)
                        .frame(height: 1)
                    Image(systemName: store.isDiscoverExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("channel-discover-toggle")

            // 失败原因不随折叠隐藏：否则用户只看到「发现更多」是空的。
            if let error = store.discoverError {
                VStack(alignment: .leading, spacing: Space.s) {
                    InlineNotice(
                        text: L10n.string(error.messageKey, locale: locale),
                        detail: error.detailText,
                        kind: .error
                    )
                    Button(L10n.string("common.retry", locale: locale)) {
                        Task { await store.loadDiscoverable() }
                    }
                    .font(TypeFace.heading(13))
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("channel-discover-retry")
                }
            }

            if store.isDiscoverExpanded {
                if store.discoverError != nil {
                    EmptyView()
                } else if store.discoverableChannels.isEmpty {
                    Text(L10n.string("channel.discover.empty", locale: locale))
                        .font(TypeFace.footnote)
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(store.discoverableChannels) { channel in
                        DiscoverableChannelRow(
                            channel: channel,
                            // 预览色按 id 稳定取，避免每次渲染都换一个「建议色」。
                            colorIndex: ChannelTint.fallbackIndex(for: channel.id),
                            isPending: store.pendingChannelIDs.contains(channel.id),
                            onSubscribe: {
                                Task {
                                    // 用与预览一致的稳定色，避免「看到的颜色」和「订阅后得到的颜色」不同。
                                    let index = ChannelTint.fallbackIndex(for: channel.id)
                                    if let subscribed = await store.subscribe(channel.id, colorIndex: index) {
                                        env.channelColors.setColorIndex(index, for: subscribed.id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(.top, Space.l)
        .accessibilityIdentifier("channel-discover-section")
    }

    private func sectionHeader(_ key: String) -> some View {
        HStack(spacing: Space.s) {
            Text(L10n.string(key, locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            Rectangle()
                .fill(Palette.line)
                .frame(height: 1)
        }
        .padding(.top, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("channel-section-\(key)")
    }

    private func track(_ channel: Channel, store: ChannelStore) {
        store.updateVisibleChannels(store.visibleChannelIDs.union([channel.id]))
        store.startPolling()
    }

    private func untrack(_ channel: Channel, store: ChannelStore) {
        var visible = store.visibleChannelIDs
        visible.remove(channel.id)
        store.updateVisibleChannels(visible)
        if visible.isEmpty {
            store.stopPolling()
        }
    }
}

// MARK: - 我的频道卡

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
                if channel.kind.isFollow {
                    ChannelBadge(textKey: "channel.kind.follow")
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
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("channel-card-\(channel.id)")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.surface)
    }

    /// 运行状态三分法：进行中绿、错过中性灰、失败警示色。
    private var statusChip: StatusChip? {
        guard channel.enabled else {
            return StatusChip(style: .neutral, text: L10n.string("channel.state.disabled", locale: locale))
        }
        return RunStatusChip.make(run: run, locale: locale)
    }

    /// 「周一、三、五 08:00」「每天 07:30」「每周二 09:00」
    private var scheduleText: String? {
        ScheduleDisplay.summary(channel.schedule, locale: locale)
    }
}

// MARK: - 订阅频道卡（只读）
//
// 不渲染开关、编辑、立即运行、删除：服务端对这些操作返回 403 / 404。

struct SubscribedChannelCard: View {
    let channel: Channel
    let run: Run?
    var colorIndex: Int?

    @Environment(\.appLocale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                ChannelDot(channelID: channel.id, diameter: 8, colorIndex: colorIndex)
                Text(channel.name)
                    .font(TypeFace.heading(15))
                    .foregroundStyle(Palette.ink)
                ChannelBadge(textKey: "channel.kind.subscribed")
                if channel.kind.isFollow {
                    ChannelBadge(textKey: "channel.kind.follow")
                }
                Spacer(minLength: 0)
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
                if let status = RunStatusChip.make(run: run, locale: locale) {
                    status
                }
                if let scheduleText {
                    Text(scheduleText)
                        .font(TypeFace.condensed(11, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.top, 11)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subscribed-card-\(channel.id)")
    }

    private var scheduleText: String? {
        ScheduleDisplay.summary(channel.schedule, locale: locale)
    }
}

// MARK: - 可订阅行

struct DiscoverableChannelRow: View {
    let channel: Channel
    var colorIndex: Int?
    let isPending: Bool
    var onSubscribe: () -> Void

    @Environment(\.appLocale) private var locale

    var body: some View {
        HStack(spacing: Space.m) {
            ChannelDot(channelID: channel.id, diameter: 8, colorIndex: colorIndex)

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(TypeFace.body(14.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if !channel.prompt.isEmpty {
                    Text(channel.prompt)
                        .font(TypeFace.footnote)
                        .foregroundStyle(Palette.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: onSubscribe) {
                if isPending {
                    ProgressView().controlSize(.small)
                } else {
                    Text(L10n.string("channel.subscribe.action", locale: locale))
                        .font(TypeFace.condensed(11, weight: .semibold))
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Palette.ink))
                }
            }
            .buttonStyle(.plain)
            .disabled(isPending)
            .accessibilityIdentifier("channel-subscribe-\(channel.id)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discover-row-\(channel.id)")
    }
}

// MARK: - 小徽标

struct ChannelBadge: View {
    let textKey: String
    @Environment(\.appLocale) private var locale

    var body: some View {
        Text(L10n.string(textKey, locale: locale))
            .font(TypeFace.condensed(9.5, weight: .semibold))
            .foregroundStyle(Palette.inkTertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.lineStrong, lineWidth: 1)
            }
    }
}

// MARK: - 运行状态 chip
//
// 我的频道与订阅频道共用同一套三分法。

enum RunStatusChip {
    static func make(run: Run?, locale: Locale) -> StatusChip? {
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
