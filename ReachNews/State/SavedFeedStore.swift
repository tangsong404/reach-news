import Foundation
import Observation

// MARK: - 收藏列表数据源
//
// 之前的实现只从首页已加载的 `store.briefs` 里筛收藏 ID，导致：
// 收藏过的日报一旦不在当前加载范围内（翻页、重启、切换到别的筛选），
// 就会凭空消失，收藏页因此误报「还没有收藏」。
//
// 这里改为按 ID 逐条取回（`GET /api/v1/briefs/:id`），不依赖首页列表。
// 单条失败只影响它自己，其余照常显示。

@MainActor
@Observable
final class SavedFeedStore {
    /// 已取回的日报，按 id 索引。
    private(set) var briefsByID: [String: Brief] = [:]
    /// 正在取回的 id。
    private(set) var loadingIDs: Set<String> = []
    /// 取回失败的 id，界面据此给出逐条重试。
    private(set) var failedIDs: Set<String> = []
    /// 整页刷新中。
    private(set) var isRefreshing = false

    @ObservationIgnored private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// 当前收藏的日报，按发布时间倒序；只返回已取回的那些。
    func briefs(for ids: Set<String>) -> [Brief] {
        ids.compactMap { briefsByID[$0] }.sorted { $0.createdAt > $1.createdAt }
    }

    func isLoading(_ id: String) -> Bool { loadingIDs.contains(id) }
    func didFail(_ id: String) -> Bool { failedIDs.contains(id) }

    /// 按给定顺序取回缺失的日报。
    ///
    /// 已经取回或正在取回的不重复请求；失败的重新纳入本轮（用户下拉刷新时重试）。
    func load(ids: Set<String>, force: Bool = false) async {
        let targets = ids.filter { id in
            if loadingIDs.contains(id) { return false }
            if force { return true }
            return briefsByID[id] == nil
        }
        guard !targets.isEmpty else { return }

        // 并发上限 4：收藏通常不多，但也不该一次性打满。
        await withTaskGroup(of: Void.self) { group in
            var iterator = targets.makeIterator()
            var inFlight = 0
            let limit = 4

            func addNext(_ group: inout TaskGroup<Void>) {
                guard let id = iterator.next() else { return }
                group.addTask { [weak self] in
                    await self?.loadOne(id)
                }
            }

            while inFlight < limit {
                addNext(&group)
                inFlight += 1
            }
            while await group.next() != nil {
                inFlight -= 1
                addNext(&group)
                inFlight += 1
            }
        }

        // 收藏被取消的条目顺手清掉缓存，避免长期驻留。
        let stale = Set(briefsByID.keys).subtracting(ids)
        for id in stale { briefsByID.removeValue(forKey: id) }
    }

    /// 下拉刷新：强制重取全部收藏（服务端可能有更新）。
    func refresh(ids: Set<String>) async {
        isRefreshing = true
        defer { isRefreshing = false }
        await load(ids: ids, force: true)
    }

    /// 单条重试。
    func retry(id: String) async {
        failedIDs.remove(id)
        await loadOne(id)
    }

    /// 取消收藏后立即移除，不等下一次刷新。
    func forget(id: String) {
        briefsByID.removeValue(forKey: id)
        failedIDs.remove(id)
        loadingIDs.remove(id)
    }

    private func loadOne(_ id: String) async {
        loadingIDs.insert(id)
        defer { loadingIDs.remove(id) }
        do {
            let brief = try await client.brief(id: id)
            briefsByID[id] = brief
            failedIDs.remove(id)
        } catch {
            failedIDs.insert(id)
        }
    }
}
