import Foundation
import Observation

// MARK: - 日报流
//
// 服务端没有「全量日报」端点，唯一的来源是 GET /channels/:id/briefs。
// 因此这里按频道各自维护分页游标，把各频道的一页合并成信息流的一页。
// 日报页即全部历史：按日期倒序、按 ID 去重、搜索与筛选内联。

@MainActor
@Observable
final class BriefFeedStore {
    private(set) var briefs: [Brief] = []
    private(set) var channelsByID: [String: Channel] = [:]
    private(set) var isLoadingFirstPage = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var error: APIError?
    private(set) var newBriefIDs: Set<String> = []
    private(set) var isRefreshing = false

    var searchText: String = ""
    var filter = FeedFilter()

    /// 全量日报端点的分页游标。
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let preferences: PreferencesStoring

    init(client: APIClient, preferences: PreferencesStoring) {
        self.client = client
        self.preferences = preferences
    }

    // MARK: 派生状态

    var visibleBriefs: [Brief] {
        BriefFeed.filtered(briefs, query: searchText, filter: filter)
    }

    var groupedBriefs: [(day: Date, briefs: [Brief])] {
        BriefFeed.groupedByDay(visibleBriefs)
    }

    /// 「显示 N 期」中的 N。
    var visibleCount: Int { visibleBriefs.count }

    var totalChannelCount: Int { channelsByID.count }

    var allChannels: [Channel] {
        channelsByID.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var isLoading: Bool { isLoadingFirstPage || isRefreshing }

    var isEmpty: Bool { !isLoading && briefs.isEmpty && error == nil }

    var hasNoResults: Bool {
        !isLoading && !briefs.isEmpty && visibleBriefs.isEmpty
    }

    func channel(for channelID: String) -> Channel? { channelsByID[channelID] }

    func channelName(for channelID: String) -> String {
        channelsByID[channelID]?.name ?? L10n.string("channel.unknown", locale: Locale.current)
    }

    /// 全量日报端点自带频道名，优先使用，避免频道表缺失时显示「未知频道」。
    func displayName(for brief: Brief) -> String {
        if let name = brief.channelName, !name.isEmpty { return name }
        return channelName(for: brief.channelID)
    }

    func isNew(_ brief: Brief) -> Bool { newBriefIDs.contains(brief.id) }

    // MARK: 加载

    func loadIfNeeded() async {
        guard briefs.isEmpty, !isLoadingFirstPage else { return }
        await loadFirstPage()
    }

    func loadFirstPage() async {
        guard !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        error = nil
        defer { isLoadingFirstPage = false }

        do {
            await loadAllChannels()
            resetPagination()
            let page = try await fetchNextPage()
            briefs = BriefFeed.merge(existing: [], incoming: page.items)
            hasMore = page.hasMore
            await advancePollingBaseline()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    /// 下拉刷新：重取各频道第一页并按 ID 合并。
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        error = nil
        defer { isRefreshing = false }

        do {
            await loadAllChannels()
            resetPagination()
            let page = try await fetchNextPage()
            briefs = BriefFeed.merge(existing: briefs, incoming: page.items)
            hasMore = page.hasMore
            await advancePollingBaseline()
        } catch let apiError as APIError {
            if apiError.isOffline {
                // 断网时不展示任何历史内容（ADR 0003）。
                briefs = []
                hasMore = false
            }
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(appearing brief: Brief) async {
        guard let last = briefs.last, last.id == brief.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchNextPage()
            briefs = BriefFeed.merge(existing: briefs, incoming: page.items)
            hasMore = page.hasMore
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    /// 筛选需要更早内容时，持续加载到覆盖范围起点或到达数据边界。
    func loadUntilCoveringFilter() async {
        guard let bound = filter.requiredLowerBound else { return }
        var rounds = 0
        while hasMore, !BriefFeed.coversLowerBound(briefs, bound: bound), rounds < 20 {
            let previousCount = briefs.count
            await loadMore()
            rounds += 1
            if briefs.count == previousCount { break }
        }
    }

    /// 频道配置改动后刷新频道名与开关状态。
    func reloadChannels() async {
        await loadAllChannels()
    }

    // MARK: 内部分页

    private struct FeedPage {
        let items: [Brief]
        let hasMore: Bool
    }

    private func resetPagination() {
        nextCursor = nil
        hasMore = true
    }

    /// 取「一页」信息流。后端已提供跨频道全量日报端点，一次请求即可。
    private func fetchNextPage() async throws -> FeedPage {
        // 频道表仍用于着色与名称兜底；取失败不阻断日报加载。
        if channelsByID.isEmpty {
            await loadAllChannels()
        }
        let page = try await client.allBriefs(cursor: nextCursor, limit: Pagination.defaultLimit)
        nextCursor = page.nextCursor
        return FeedPage(items: page.items, hasMore: page.nextCursor != nil)
    }

    private func loadAllChannels() async {
        var cursor: String?
        var collected: [Channel] = []
        var rounds = 0
        repeat {
            do {
                let page = try await client.channels(cursor: cursor, limit: Pagination.maxLimit)
                collected.append(contentsOf: page.items)
                cursor = page.nextCursor
            } catch {
                break
            }
            rounds += 1
        } while cursor != nil && rounds < 20

        if !collected.isEmpty {
            var map: [String: Channel] = [:]
            for channel in collected where channel.kind.isUserVisible {
                map[channel.id] = channel
            }
            channelsByID = map
        }
    }

    /// 轮询：按 lastSeenAt 取新增内容并推进基线。
    private func advancePollingBaseline() async {
        let baseline = preferences.lastSeenAt
        do {
            let payload = try await client.cursor(since: baseline)
            let knownIDs = Set(briefs.map(\.id))
            newBriefIDs.formUnion(payload.briefs.filter { !knownIDs.contains($0.id) }.map(\.id))
            if let advanced = PollingBaseline.next(baseline: baseline, payload: payload) {
                preferences.lastSeenAt = advanced
            }
            if !payload.channels.isEmpty {
                await loadAllChannels()
            }
        } catch {
            // 轮询失败不影响已加载内容；下一次刷新继续。
        }
    }

    func clearNewContentMarkers() {
        newBriefIDs.removeAll()
    }
}
