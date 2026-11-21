import Foundation
import Observation

// MARK: - 日报详情
//
// 详情页按需拉素材（列表里不带正文），并记住每个素材的加载状态。
// content 只解析，永不渲染。

@MainActor
@Observable
final class BriefDetailStore {
    private(set) var brief: Brief
    private(set) var materialsByID: [String: Material] = [:]
    private(set) var loadingMaterialIDs: Set<String> = []
    private(set) var failedMaterialIDs: Set<String> = []
    private(set) var error: APIError?

    /// 已展开的条目（按 Entry.id）。
    var expandedEntryIDs: Set<String> = []

    @ObservationIgnored private let client: APIClient

    init(brief: Brief, client: APIClient) {
        self.brief = brief
        self.client = client
    }

    var channelID: String { brief.channelID }

    func isExpanded(_ entry: Entry) -> Bool {
        expandedEntryIDs.contains(entry.id)
    }

    func toggleExpanded(_ entry: Entry) {
        if expandedEntryIDs.contains(entry.id) {
            expandedEntryIDs.remove(entry.id)
        } else {
            expandedEntryIDs.insert(entry.id)
            Task { await self.loadMaterials(for: entry) }
        }
    }

    func material(id: String) -> Material? {
        materialsByID[id]
    }

    func isLoading(materialID: String) -> Bool {
        loadingMaterialIDs.contains(materialID)
    }

    func didFail(materialID: String) -> Bool {
        failedMaterialIDs.contains(materialID)
    }

    /// 展开条目时按需取回该条目的素材。
    func loadMaterials(for entry: Entry) async {
        let missing = entry.materialIDs.filter { materialsByID[$0] == nil && !loadingMaterialIDs.contains($0) }
        guard !missing.isEmpty else { return }

        for materialID in missing {
            loadingMaterialIDs.insert(materialID)
            defer { loadingMaterialIDs.remove(materialID) }
            do {
                let material = try await client.material(briefID: brief.id, materialID: materialID)
                materialsByID[materialID] = material
                failedMaterialIDs.remove(materialID)
            } catch let apiError as APIError {
                failedMaterialIDs.insert(materialID)
                if apiError == .unauthorized {
                    error = apiError
                    return
                }
            } catch {
                failedMaterialIDs.insert(materialID)
            }
        }
    }
}

// MARK: - 追问
//
// 服务端回答是确定性拼接，不是 LLM：不流式、不逐字、不显示「正在思考」。

@MainActor
@Observable
final class AskStore {
    private(set) var turns: [AskTurn] = []
    private(set) var isLoadingHistory = false
    private(set) var isLoadingMore = false
    private(set) var isSending = false
    private(set) var hasMore = false
    private(set) var error: APIError?
    private(set) var sendFailureMessage: String?
    /// 最近一条回答引用的素材 ID（服务端 citedItemIds）。
    private(set) var lastCitedItemIDs: [String] = []
    /// 服务端明确标注这是确定性应答，未接 LLM。
    private(set) var lastAnswerWasDeterministic = false
    /// 引用素材的标题与来源域，按需拉取并缓存。
    private(set) var citedMaterials: [String: Material] = [:]

    /// 输入框内容；发送失败时保留，不清空。
    var draft: String = ""

    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private let briefID: String
    @ObservationIgnored private let client: APIClient

    init(briefID: String, client: APIClient) {
        self.briefID = briefID
        self.client = client
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var isEmpty: Bool {
        !isLoadingHistory && turns.isEmpty
    }

    func loadHistoryIfNeeded() async {
        guard turns.isEmpty, !isLoadingHistory else { return }
        await loadHistory()
    }

    func loadHistory() async {
        isLoadingHistory = true
        error = nil
        defer { isLoadingHistory = false }
        do {
            let page = try await client.askHistory(briefID: briefID, cursor: nil, limit: Pagination.defaultLimit)
            turns = page.items.sorted { $0.createdAt < $1.createdAt }
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.askHistory(briefID: briefID, cursor: cursor, limit: Pagination.defaultLimit)
            var seen = Set(turns.map(\.id))
            var merged = turns
            for turn in page.items where seen.insert(turn.id).inserted {
                merged.append(turn)
            }
            turns = merged.sorted { $0.createdAt < $1.createdAt }
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }

        isSending = true
        sendFailureMessage = nil
        defer { isSending = false }

        let userTurn = AskTurn(
            id: "local-user-\(UUID().uuidString)",
            role: .user,
            message: message,
            createdAt: Date()
        )
        turns.append(userTurn)

        do {
            let response = try await client.ask(briefID: briefID, message: message)
            turns.append(response.turn)
            lastCitedItemIDs = response.citedItemIDs
            lastAnswerWasDeterministic = response.isDeterministic
            draft = ""
            await loadCitedMaterials()
        } catch let apiError as APIError {
            // 失败时保留已输入内容，并把失败的那一轮留成可重试状态。
            draft = message
            sendFailureMessage = apiError.messageKey
            error = apiError
        } catch {
            draft = message
            sendFailureMessage = APIError.transport("").messageKey
            self.error = .transport(error.localizedDescription)
        }
    }

    func dismissSendFailure() {
        sendFailureMessage = nil
    }

    /// 引用卡只显示标题与来源域；`content` 永不渲染。
    func materialTitle(for itemID: String) -> String {
        citedMaterials[itemID]?.title ?? itemID
    }

    func materialHost(for itemID: String) -> String? {
        citedMaterials[itemID]?.host
    }

    /// 按需拉取引用素材；单个失败不影响其余条目。
    private func loadCitedMaterials() async {
        let missing = lastCitedItemIDs.filter { citedMaterials[$0] == nil }
        for itemID in missing {
            do {
                let material = try await client.material(briefID: briefID, materialID: itemID)
                citedMaterials[itemID] = material
            } catch {
                // 取不到时引用卡退化显示 itemId 本身，不隐藏该条。
            }
        }
    }
}

// MARK: - 收藏
//
// 仅本机集合，不同步服务端。

@MainActor
@Observable
final class SavedStore {
    private(set) var savedIDs: Set<String>

    @ObservationIgnored private let storage: SavedBriefsStoring

    init(storage: SavedBriefsStoring) {
        self.storage = storage
        self.savedIDs = storage.savedBriefIDs
    }

    func isSaved(_ briefID: String) -> Bool {
        savedIDs.contains(briefID)
    }

    func toggle(_ briefID: String) {
        savedIDs = storage.toggle(briefID)
    }
}

// MARK: - 频道颜色（仅本机）

@MainActor
@Observable
final class ChannelColorStore {
    private(set) var assignments: [String: Int]

    @ObservationIgnored private let storage: ChannelColorStoring

    init(storage: ChannelColorStoring) {
        self.storage = storage
        self.assignments = storage.assignments
    }

    /// 本地设置的颜色索引；未设置时返回 nil，由视图回退到按 id 的稳定色。
    func colorIndex(for channelID: String) -> Int? {
        assignments[channelID]
    }

    /// 实际使用的索引（含回退），用于取色与展示当前选中项。
    func effectiveIndex(for channelID: String) -> Int {
        assignments[channelID] ?? ChannelTint.fallbackIndex(for: channelID)
    }

    func setColorIndex(_ index: Int, for channelID: String) {
        storage.setColorIndex(index, for: channelID)
        assignments = storage.assignments
    }

    /// 新建频道时挑一个当前用得最少的颜色。
    func suggestedIndex() -> Int {
        ChannelTint.leastUsedIndex(among: Array(assignments.values))
    }

    func forget(_ channelID: String) {
        storage.remove(channelID)
        assignments = storage.assignments
    }
}
