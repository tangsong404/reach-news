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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    brandHeader
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

    private var brandHeader: some View {
        HStack(spacing: Space.s) {
            BrandMark(assetName: "LogoMarkInk", size: 24)
            Text("Reach News")
                .font(TypeFace.heading(15))
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func content(_ store: BriefFeedStore) -> some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            metaLines(store)
            searchRow(store)

            if store.filter.isActive {
                activeFilterSummary(store)
            }

            if store.isLoadingFirstPage {
                Spacer()
                LoadingLine(text: L10n.string("feed.loading", locale: locale))
                Spacer()
            } else if let error = store.error, store.briefs.isEmpty {
                Spacer()
                errorState(error, store: store)
                Spacer()
            } else if store.isEmpty {
                Spacer()
                emptyState()
                Spacer()
            } else if store.hasNoResults {
                Spacer()
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
                Spacer()
            } else {
                feedList(store)
            }
        }
        .sheet(isPresented: $showFilter) {
            FeedFilterSheet(store: store, isPresented: $showFilter)
                .presentationDetents(SheetMetrics.detents)
                .presentationDragIndicator(.visible)
        }
    }

    /// 只保留频道数与期数；不显示当日日期，也不显示排序说明。
    private func metaLines(_ store: BriefFeedStore) -> some View {
        HStack(spacing: 7) {
            MetaLine(text: L10n.format("feed.channelCount", locale: locale, store.totalChannelCount))
            DotSeparator()
            MetaLine(text: L10n.format("feed.briefCount", locale: locale, store.briefs.count))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed-meta")
    }

    private func searchRow(_ store: BriefFeedStore) -> some View {
        @Bindable var store = store
        return HStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkTertiary)
                TextField(
                    String(localized: "feed.search.placeholder"),
                    text: $store.searchText
                )
                .font(TypeFace.body(13.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("feed-search-field")
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String(localized: "feed.search.clear")))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.5)
            }

            Button {
                showFilter = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.string("feed.filter.button", locale: locale))
                        .font(TypeFace.heading(12.5))
                    if store.filter.activeDimensionCount > 0 {
                        Text("\(store.filter.activeDimensionCount)")
                            .font(TypeFace.condensed(9.5, weight: .bold))
                            .foregroundStyle(store.filter.isActive ? Palette.canvas : Palette.inkSecondary)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(
                                store.filter.isActive ? Palette.canvas.opacity(0.22) : Palette.chip,
                                in: Capsule()
                            )
                    }
                }
                .foregroundStyle(store.filter.isActive ? Palette.canvas : Palette.ink)
                .padding(.horizontal, Space.m)
                .padding(.vertical, 9)
                .background(
                    store.filter.isActive ? Palette.ink : Palette.surface.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: store.filter.isActive ? 0 : 0.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed-filter-button")
            .accessibilityLabel(Text(L10n.string("feed.filter.button", locale: locale)))
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.m)
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
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "filter.remove")))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Palette.chip, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func feedList(_ store: BriefFeedStore) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(store.groupedBriefs, id: \.day) { group in
                    DayRule(title: DisplayTime.dayRuleTitle(group.day, now: Date(), locale: locale))
                        .padding(.horizontal, Space.xl)
                        .padding(.top, Space.l)
                        .padding(.bottom, Space.xs)

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
                        .buttonStyle(.plain)
                        .padding(.horizontal, Space.xl)
                        .task {
                            await store.loadMoreIfNeeded(appearing: brief)
                        }
                    }
                }

                if store.isLoadingMore {
                    LoadingLine(text: L10n.string("feed.loadingMore", locale: locale))
                } else if !store.hasMore && !store.briefs.isEmpty {
                    Text(L10n.string("feed.endOfFeed", locale: locale))
                        .font(TypeFace.body(11.5))
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.l)
                }
            }
            .padding(.bottom, 96)
        }
        .refreshable {
            await store.refresh()
        }
        .accessibilityIdentifier("feed-list")
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
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
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
                        .strokeBorder(isOn ? Palette.ink : Palette.lineStrong, lineWidth: 1.4)
                        .frame(width: 17, height: 17)
                    if isOn {
                        Circle()
                            .fill(Palette.ink)
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
        .buttonStyle(.plain)
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
