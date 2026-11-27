import SwiftUI

// MARK: - 日报流
//
// 日报页即全部历史：日期分组倒序、搜索常驻、筛选收在面板里。

struct BriefFeedView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @State private var store: BriefFeedStore?
    @State private var showFilter = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let store {
                    content(store)
                } else {
                    LoadingLine(text: L10n.string("common.loading", locale: locale))
                }
            }
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            // 一级页面用大标题（HIG：大标题帮助定位，滚动时自动收成标准标题）。
            .navigationTitle(L10n.string("tab.briefs", locale: locale))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterToolbarButton(store)
                }
            }
            .navigationDestination(for: Brief.self) { brief in
                BriefDetailView(brief: brief, store: env.makeDetailStore(brief: brief))
            }
        }
        .task {
            if store == nil {
                store = env.feed
            }
            await store?.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func content(_ store: BriefFeedStore) -> some View {
        @Bindable var store = store

        // 品牌行、计数行、日期分组都在 List 里，跟着内容一起滚走；
        // 只有搜索框（系统 searchable）固定在导航栏下方。
        List {
            brandRow
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Space.s, leading: Space.xl, bottom: Space.xs, trailing: Space.xl))

            metaLines(store)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Space.xl, bottom: Space.s, trailing: Space.xl))

            if store.filter.isActive {
                activeFilterSummary(store)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Space.s, trailing: 0))
            }

            if store.isLoadingFirstPage {
                LoadingLine(text: L10n.string("feed.loading", locale: locale))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if let error = store.error, store.briefs.isEmpty {
                errorState(error, store: store)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if store.isEmpty {
                emptyState()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if store.hasNoResults {
                MessageStateView(
                    title: L10n.string("feed.noResults.title", locale: locale),
                    message: L10n.string("feed.noResults.message", locale: locale),
                    kind: .empty,
                    actionTitle: L10n.string("common.clearFilters", locale: locale),
                    action: {
                        store.searchText = ""
                        store.filter = FeedFilter()
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                feedRows(store)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refresh()
        }
        .accessibilityIdentifier("feed-list")
        // 系统搜索框：自带查找图标、清除按钮、键盘联动与滚动固定行为。
        .searchable(
            text: $store.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(L10n.string("feed.search.placeholder", locale: locale))
        )
        .sheet(isPresented: $showFilter) {
            FeedFilterSheet(store: store, isPresented: $showFilter)
                .presentationDetents(SheetMetrics.detents)
                .presentationDragIndicator(.visible)
        }
    }

    /// 首页品牌区：图形 + 字标，随内容滚动，不占导航栏。
    private var brandRow: some View {
        HStack(spacing: Space.s) {
            BrandMark(size: 26)
            Text("Reach News")
                .font(TypeFace.heading(19))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("feed-brand")
    }

    /// 筛选入口放工具栏：HIG 工具栏承载作用于内容的命令，搜索框则由系统 searchable 承担。
    @ViewBuilder
    private func filterToolbarButton(_ store: BriefFeedStore?) -> some View {
        let isActive = store?.filter.isActive ?? false
        let dimensions = store?.filter.activeDimensionCount ?? 0
        Button {
            showFilter = true
        } label: {
            // 三道递减的横线是系统里表示「筛选/排序」的图形；
            // 带圈的版本容易被读成列表，所以用不带圈的。
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isActive ? env.appearance.accent : Palette.ink)
        }
        .buttonStyle(.pressable)
        .disabled(store == nil)
        .accessibilityIdentifier("feed-filter-button")
        .accessibilityLabel(Text(L10n.string("feed.filter.button", locale: locale)))
        .accessibilityValue(
            Text(dimensions > 0 ? "\(dimensions)" : L10n.string("common.off", locale: locale))
        )
    }

    /// 只保留频道数与期数；不显示当日日期，也不显示排序说明。
    private func metaLines(_ store: BriefFeedStore) -> some View {
        HStack(spacing: 7) {
            MetaLine(text: L10n.format("feed.channelCount", locale: locale, store.totalChannelCount))
            DotSeparator()
            MetaLine(text: L10n.format("feed.briefCount", locale: locale, store.briefs.count))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed-meta")
    }

    private func activeFilterSummary(_ store: BriefFeedStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                if store.filter.time != .all {
                    activeFilterChip(
                        title: L10n.string(store.filter.time.labelKey, locale: locale),
                        channelID: nil
                    ) {
                        store.filter.time = .all
                        store.filter.startDate = nil
                        store.filter.endDate = nil
                    }
                }
                ForEach(Array(store.filter.channelIDs.sorted()), id: \.self) { channelID in
                    activeFilterChip(
                        title: store.channelName(for: channelID),
                        channelID: channelID
                    ) {
                        store.filter.channelIDs.remove(channelID)
                    }
                }
            }
            .padding(.horizontal, Space.l)
        }
        .padding(.bottom, Space.s)
    }

    private func activeFilterChip(title: String, channelID: String?, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            if let channelID {
                ChannelDot(
                    channelID: channelID,
                    diameter: 6,
                    colorIndex: env.channelColors.colorIndex(for: channelID)
                )
            }
            Text(title)
                .font(TypeFace.label(11))
                .foregroundStyle(Palette.inkSecondary)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text(String(localized: "filter.remove")))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Palette.chip, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// 日期分组与行都作为普通 List 行（不是 Section 头），
    /// 这样向下滚动时它们跟着内容走，不会吸顶留在原地。
    @ViewBuilder
    private func feedRows(_ store: BriefFeedStore) -> some View {
        ForEach(store.groupedBriefs, id: \.day) { group in
            Text(DisplayTime.dayRuleTitle(group.day, now: Date(), locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
                .textCase(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.l)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Space.xl, bottom: Space.xs, trailing: Space.xl))

            ForEach(group.briefs) { brief in
                NavigationLink(value: brief) {
                    BriefRow(
                        brief: brief,
                        channelName: store.displayName(for: brief),
                        channelID: brief.channelID,
                        isNew: store.isNew(brief),
                        colorIndex: env.channelColors.colorIndex(for: brief.channelID)
                    )
                }
                .listRowBackground(Color.clear)
                .task {
                    await store.loadMoreIfNeeded(appearing: brief)
                }
            }
        }

        if store.isLoadingMore {
            LoadingLine(text: L10n.string("feed.loadingMore", locale: locale))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if !store.hasMore && !store.briefs.isEmpty {
            Text(L10n.string("feed.endOfFeed", locale: locale))
                .font(TypeFace.body(11.5))
                .foregroundStyle(Palette.inkTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.l)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private func emptyState() -> some View {
        MessageStateView(
            title: L10n.string("feed.empty.title", locale: locale),
            message: L10n.string("feed.empty.message", locale: locale),
            kind: .empty
        )
    }

    private func errorState(_ error: APIError, store: BriefFeedStore) -> some View {
        MessageStateView(
            title: L10n.string(error.messageKey, locale: locale),
            message: error.isOffline ? L10n.string("error.offline.detail", locale: locale) : error.detailText,
            kind: .error(error),
            actionTitle: L10n.string("common.retry", locale: locale),
            action: {
                Task { await store.refresh() }
            }
        )
    }
}

// MARK: - 日报行

struct BriefRow: View {
    let brief: Brief
    let channelName: String
    let channelID: String
    let isNew: Bool
    var colorIndex: Int?

    @Environment(\.appLocale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(brief.title)
                    .font(TypeFace.heading(14.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if isNew {
                    Text(L10n.string("feed.new", locale: locale))
                        .font(TypeFace.condensed(9, weight: .bold))
                        .foregroundStyle(Palette.onInverse)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Palette.inverseSurface, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Spacer(minLength: 0)
            }

            // 描述非空时展示在标题下，一到两行截断；为空时不留空洞。
            if let summary = brief.displaySummary {
                Text(summary)
                    .font(TypeFace.body(12.5))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("brief-row-summary")
            }

            // 分组数与素材数来自 sections，读者端不再展示。
            HStack(spacing: 7) {
                ChannelDot(channelID: channelID, colorIndex: colorIndex)
                Text(channelName)
                    .font(TypeFace.label(11))
                    .foregroundStyle(Palette.inkSecondary)
                DotSeparator()
                MetaLine(text: DisplayTime.clock(brief.createdAt, locale: locale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed-row-\(brief.id)")
    }
}

// MARK: - 筛选面板

struct FeedFilterSheet: View {
    @Bindable var store: BriefFeedStore
    @Binding var isPresented: Bool
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    @State private var draft: FeedFilter = FeedFilter()
    @State private var customStart: Date = Date()
    @State private var customEnd: Date = Date()
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 结果数量替代原来的按钮文案，让用户知道当前会筛出多少。
                    sheetHeading("filter.time.heading")
                    ForEach(FeedTimeFilter.allCases) { option in
                        optionRow(
                            title: L10n.string(option.labelKey, locale: locale),
                            isOn: draft.time == option,
                            channelID: nil
                        ) {
                            draft.time = option
                        }
                    }

                    if draft.time == .custom {
                        dateRangeFields
                    }

                    sheetHeading("filter.channel.heading")
                        .padding(.top, Space.xl)
                    ForEach(store.allChannels) { channel in
                        optionRow(
                            title: channel.name,
                            isOn: draft.channelIDs.contains(channel.id),
                            channelID: channel.id
                        ) {
                            if draft.channelIDs.contains(channel.id) {
                                draft.channelIDs.remove(channel.id)
                            } else {
                                draft.channelIDs.insert(channel.id)
                            }
                        }
                    }

                    if store.allChannels.isEmpty {
                        Text(L10n.string("filter.channel.none", locale: locale))
                            .font(TypeFace.body(12.5))
                            .foregroundStyle(Palette.inkTertiary)
                            .padding(.vertical, Space.s)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xl)
            }
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("feed.filter.button", locale: locale))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("filter.reset", locale: locale)) {
                        draft = FeedFilter()
                        customStart = Date()
                        customEnd = Date()
                    }
                    .font(TypeFace.body(15))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("filter-reset")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        apply()
                    } label: {
                        if isApplying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.string("filter.apply.short", locale: locale))
                                .font(TypeFace.heading(15))
                        }
                    }
                    .disabled(isApplying)
                    .accessibilityIdentifier("filter-apply")
                }
            }
        }
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        .onAppear {
            draft = store.filter
            customStart = store.filter.startDate ?? Date()
            customEnd = store.filter.endDate ?? Date()
        }
        .accessibilityIdentifier("feed-filter-sheet")
    }

    /// 「显示 N 期」：当前草稿条件下已加载的期数。
    private var previewCount: Int {
        BriefFeed.filtered(store.briefs, query: store.searchText, filter: effectiveDraft)
            .count
    }

    private var effectiveDraft: FeedFilter {
        var value = draft
        if draft.time == .custom {
            value.startDate = customStart
            value.endDate = customEnd
        }
        return value
    }

    private func apply() {
        isApplying = true
        store.filter = effectiveDraft
        isPresented = false
        Task {
            // 需要更早内容时持续加载到覆盖范围起点。
            await store.loadUntilCoveringFilter()
            isApplying = false
        }
    }

    private func sheetHeading(_ key: String) -> some View {
        Text(L10n.string(key, locale: locale))
            .font(TypeFace.label(11))
            .tracking(1)
            .foregroundStyle(Palette.inkTertiary)
            .padding(.bottom, Space.s)
    }

    private func optionRow(title: String, isOn: Bool, channelID: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if let channelID {
                    ChannelDot(
                        channelID: channelID,
                        colorIndex: env.channelColors.colorIndex(for: channelID)
                    )
                }
                Text(title)
                    .font(TypeFace.body(14))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .strokeBorder(isOn ? env.appearance.accent : Palette.lineStrong, lineWidth: 1.4)
                        .frame(width: 17, height: 17)
                    if isOn {
                        Circle()
                            .fill(env.appearance.accent)
                            .frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.canvas)
                    }
                }
            }
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.line).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("filter-option-\(title)")
    }

    private var dateRangeFields: some View {
        HStack(spacing: Space.m) {
            dateField(labelKey: "filter.custom.start", date: $customStart)
            Text("–")
                .font(TypeFace.body(12))
                .foregroundStyle(Palette.inkTertiary)
            dateField(labelKey: "filter.custom.end", date: $customEnd)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 11)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, Space.m)
    }

    private func dateField(labelKey: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string(labelKey, locale: locale))
                .font(TypeFace.label(9.5))
                .tracking(0.8)
                .foregroundStyle(Palette.inkTertiary)
            DatePicker(
                "",
                selection: date,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, locale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
