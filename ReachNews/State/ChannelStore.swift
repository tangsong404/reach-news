import Foundation
import Observation

// MARK: - 频道列表
//
// 频道页由三种来源组成：我创建的、我订阅的、可订阅的（discover=1）。
// 可写性一律看 owner：订阅者只读，编辑 / 删除 / 触发运行都不提供。
// enabled 开关即时生效、失败回滚；运行状态只对可见行轮询。

@MainActor
@Observable
final class ChannelStore {
    /// 我创建的频道（owner == creator）。
    private(set) var myChannels: [Channel] = []
    /// 我订阅的频道（owner == subscriber && subscribed）。
    private(set) var subscribedChannels: [Channel] = []
    /// 可订阅的频道（discover=1 里 subscribed == false 且不是自己创建的）。
    private(set) var discoverableChannels: [Channel] = []

    private(set) var latestRuns: [String: Run] = [:]
    private(set) var isLoading = false
    /// 默认列表（我的 + 订阅的）的错误。
    private(set) var error: APIError?
    /// 「发现更多」的错误；单独呈现，不影响前两段。
    private(set) var discoverError: APIError?
    private(set) var isDiscovering = false
    /// 折叠时也保留数量提示，因此进入页面即加载。
    var isDiscoverExpanded = false

    /// 正在提交 enabled 变更或订阅动作的频道，用于禁用重复点击。
    private(set) var pendingChannelIDs: Set<String> = []

    /// 当前可见的频道 ID，由视图上报；轮询只作用于这些行。
    private(set) var visibleChannelIDs: Set<String> = []

    /// 新建频道用的连接器（仅创建流程需要）。
    private(set) var collectorSkills: [CollectorSkill] = []
    /// Historical compatibility only; production selection uses collectorSkills.
    var connectors: [Connector] { [] }
    private(set) var isCreating = false
    private(set) var createError: APIError?

    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    init(client: APIClient) {
        self.client = client
    }

    // MARK: 派生状态

    /// 我的 + 订阅的；不含可订阅项。
    var channels: [Channel] { myChannels + subscribedChannels }

    var isEmpty: Bool {
        !isLoading && myChannels.isEmpty && subscribedChannels.isEmpty && error == nil
    }

    /// 三段都空：既没有频道，也没有可订阅项。
    var isFullyEmpty: Bool {
        isEmpty && discoverableChannels.isEmpty
    }

    func channel(id: String) -> Channel? {
        myChannels.first { $0.id == id }
            ?? subscribedChannels.first { $0.id == id }
            ?? discoverableChannels.first { $0.id == id }
    }

    func latestRun(for channelID: String) -> Run? {
        latestRuns[channelID]
    }

    // MARK: 加载

    /// 默认列表与「发现更多」并行加载；单段失败只影响该段。
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        discoverError = nil
        defer { isLoading = false }

        async let defaultList: Result<[Channel], Error> = fetchAllChannels(discover: false)
        async let discoverList: Result<[Channel], Error> = fetchAllChannels(discover: true)

        // 两个请求并行；任一失败只影响自己那一段。
        // 先取 discover 再取 default：default 成功分支里的 refreshVisibleRuns 会等到最后才返回。
        let discoverResult = await discoverList
        switch discoverResult {
        case .success(let channels):
            discoverableChannels = channels.filter { $0.canSubscribe }
        case .failure(let failure):
            self.discoverError = Self.normalized(failure)
        }

        let defaultResult = await defaultList
        switch defaultResult {
        case .success(let channels):
            apply(channels)
            await refreshVisibleRuns()
        case .failure(let failure):
            self.error = Self.normalized(failure)
        }
    }

    /// 只刷新「发现更多」，用于订阅 / 取消订阅后回收列表。
    func loadDiscoverable() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        discoverError = nil
        defer { isDiscovering = false }
        do {
            let channels = try await fetchAll(discover: true)
            discoverableChannels = channels.filter { $0.canSubscribe }
        } catch {
            discoverError = Self.normalized(error)
        }
    }

    private func fetchAllChannels(discover: Bool) async -> Result<[Channel], Error> {
        do {
            return .success(try await fetchAll(discover: discover))
        } catch {
            return .failure(error)
        }
    }

    /// 按游标翻完全部页；上限防止服务端游标异常时死循环。
    private func fetchAll(discover: Bool) async throws -> [Channel] {
        var cursor: String?
        var collected: [Channel] = []
        var rounds = 0
        repeat {
            let page = try await client.channels(
                cursor: cursor,
                limit: Pagination.maxLimit,
                discover: discover
            )
            collected.append(contentsOf: page.items)
            cursor = page.nextCursor
            rounds += 1
        } while cursor != nil && rounds < 20
        return collected
    }

    /// 按 owner 拆成两段；订阅段保持服务端顺序（created_at DESC）。
    private func apply(_ channels: [Channel]) {
        myChannels = channels.filter { $0.owner.isCreator }
        subscribedChannels = channels.filter { $0.isSubscription }
    }

    private static func normalized(_ error: Error) -> APIError {
        (error as? APIError) ?? .transport(error.localizedDescription)
    }

    // MARK: 开关

    /// 乐观切换：先本地翻转，失败回滚并保留原因。只有我创建的频道有开关。
    func setEnabled(_ enabled: Bool, for channelID: String) async {
        guard let index = myChannels.firstIndex(where: { $0.id == channelID }),
              myChannels[index].canEdit else { return }
        let original = myChannels[index].enabled

        myChannels[index].enabled = enabled
        pendingChannelIDs.insert(channelID)
        error = nil
        defer { pendingChannelIDs.remove(channelID) }

        do {
            let updated = try await client.patchChannel(
                id: channelID,
                changes: ChannelChanges(enabled: enabled)
            )
            replace(updated)
        } catch {
            if let currentIndex = myChannels.firstIndex(where: { $0.id == channelID }) {
                myChannels[currentIndex].enabled = original
            }
            self.error = Self.normalized(error)
        }
    }

    // MARK: 新建

    /// 创建流程所需的数据。连接器是必需的（否则建出的频道跑起来必 missed）。
    func loadCreationOptions() async {
        createError = nil
        do {
            collectorSkills = try await client.collectorSkills()
        } catch {
            createError = Self.normalized(error)
        }
    }

    /// 直接新建频道。
    func create(
        name: String,
        prompt: String,
        tone: String,
        schedule: Schedule,
        collectorSkillIDs: [String],
        enabled: Bool = true
    ) async -> Channel? {
        guard !isCreating else { return nil }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            let created = try await client.createChannel(
                name: name,
                prompt: prompt,
                tone: tone,
                schedule: schedule,
                collectorSkillIDs: collectorSkillIDs,
                enabled: enabled
            )
            replace(created)
            return created
        } catch {
            createError = Self.normalized(error)
            return nil
        }
    }

    func create(name: String, prompt: String, tone: String, schedule: Schedule,
                connectorIDs: [String]) async -> Channel? {
        createError = .collectorMigrationRequired
        return nil
    }

    // MARK: 订阅

    /// 订阅一个已公开频道。重复订阅是幂等的，200 与 201 都按成功处理。
    @discardableResult
    func subscribe(_ channelID: String, colorIndex: Int) async -> Channel? {
        guard !pendingChannelIDs.contains(channelID) else { return nil }
        pendingChannelIDs.insert(channelID)
        discoverError = nil
        defer { pendingChannelIDs.remove(channelID) }

        do {
            try await client.subscribe(
                channelID: channelID,
                color: ChannelTint.paletteColorValue(at: colorIndex)
            )
            // 订阅响应只带订阅对象，用一次单频道读取拿到完整 DTO 以刷新卡片。
            let subscribed = try await client.channel(id: channelID)
            replace(subscribed)
            discoverableChannels.removeAll { $0.id == channelID }
            return subscribed
        } catch {
            discoverError = Self.normalized(error)
            return nil
        }
    }

    /// 只改订阅颜色；返回完整 channel DTO，直接刷新列表项与详情。
    @discardableResult
    func updateSubscriptionColor(_ channelID: String, colorIndex: Int) async -> Channel? {
        guard !pendingChannelIDs.contains(channelID) else { return nil }
        pendingChannelIDs.insert(channelID)
        defer { pendingChannelIDs.remove(channelID) }

        do {
            let updated = try await client.updateSubscriptionColor(
                channelID: channelID,
                color: ChannelTint.paletteColorValue(at: colorIndex)
            )
            replace(updated)
            return updated
        } catch {
            self.error = Self.normalized(error)
            return nil
        }
    }

    /// 取消订阅：频道与本机列表立即移除；频道与历史日报在服务端保留。
    @discardableResult
    func unsubscribe(_ channelID: String) async -> Bool {
        guard !pendingChannelIDs.contains(channelID) else { return false }
        pendingChannelIDs.insert(channelID)
        defer { pendingChannelIDs.remove(channelID) }

        do {
            try await client.unsubscribe(channelID: channelID)
            subscribedChannels.removeAll { $0.id == channelID }
            latestRuns.removeValue(forKey: channelID)
            // 取消后它会重新变成可订阅项。
            await loadDiscoverable()
            return true
        } catch let apiError as APIError where apiError == .notFound {
            // 关系已不存在：按已取消处理。
            subscribedChannels.removeAll { $0.id == channelID }
            return true
        } catch {
            self.error = Self.normalized(error)
            return false
        }
    }

    /// fork 成自己的频道；服务端同时取消原订阅。
    @discardableResult
    func fork(_ channelID: String) async -> Channel? {
        guard !isCreating else { return nil }
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await client.forkChannel(id: channelID)
            subscribedChannels.removeAll { $0.id == channelID }
            latestRuns.removeValue(forKey: channelID)
            myChannels.insert(created, at: 0)
            discoverableChannels.removeAll { $0.id == channelID }
            return created
        } catch {
            self.error = Self.normalized(error)
            return nil
        }
    }

    // MARK: 编辑与删除

    /// 软删除频道（只有创建者）。
    /// - 成功：从列表移除。
    /// - 404（已删除）：按已删除处理，同样移除。
    /// - 409（有运行在跑）：不删除，返回失败原因。
    @discardableResult
    func delete(_ channelID: String) async -> Bool {
        createError = nil
        do {
            _ = try await client.deleteChannel(id: channelID)
            removeLocally(channelID)
            return true
        } catch let apiError as APIError {
            if apiError == .notFound {
                removeLocally(channelID)
                return true
            }
            createError = apiError
            return false
        } catch {
            createError = Self.normalized(error)
            return false
        }
    }

    /// 用服务端返回的频道对象替换本地项；不存在时按 owner 落到对应段。
    func replace(_ channel: Channel) {
        if let index = myChannels.firstIndex(where: { $0.id == channel.id }) {
            myChannels[index] = channel
            if !channel.owner.isCreator {
                myChannels.remove(at: index)
                if channel.isSubscription { subscribedChannels.insert(channel, at: 0) }
            }
            return
        }
        if let index = subscribedChannels.firstIndex(where: { $0.id == channel.id }) {
            if channel.owner.isCreator {
                subscribedChannels.remove(at: index)
                myChannels.insert(channel, at: 0)
            } else if channel.isSubscription {
                subscribedChannels[index] = channel
            } else {
                // 订阅关系已不存在（例如在别处取消）：从订阅段移除，不再当作订阅频道渲染。
                subscribedChannels.remove(at: index)
            }
            return
        }
        if let index = discoverableChannels.firstIndex(where: { $0.id == channel.id }) {
            discoverableChannels[index] = channel
            if !channel.canSubscribe { discoverableChannels.remove(at: index) }
            if channel.isSubscription { subscribedChannels.insert(channel, at: 0) }
            return
        }
        if channel.owner.isCreator {
            myChannels.insert(channel, at: 0)
        } else if channel.isSubscription {
            subscribedChannels.insert(channel, at: 0)
        }
    }

    private func removeLocally(_ channelID: String) {
        myChannels.removeAll { $0.id == channelID }
        subscribedChannels.removeAll { $0.id == channelID }
        discoverableChannels.removeAll { $0.id == channelID }
        latestRuns.removeValue(forKey: channelID)
    }

    // MARK: 可见行轮询

    func updateVisibleChannels(_ ids: Set<String>) {
        visibleChannelIDs = ids
        guard !ids.isEmpty else { return }
        Task { await self.refreshVisibleRuns() }
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshVisibleRuns()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 只对屏幕内可见行取最近一条运行。
    func refreshVisibleRuns() async {
        for channelID in visibleChannelIDs {
            do {
                let page = try await client.runs(channelID: channelID, cursor: nil, limit: 1)
                if let run = page.items.first {
                    latestRuns[channelID] = run
                } else {
                    latestRuns.removeValue(forKey: channelID)
                }
            } catch {
                // 单个频道的运行状态取不到时保留上一次结果。
            }
        }
    }
}

// MARK: - 频道编辑

@MainActor
@Observable
final class ChannelEditor {
    let original: Channel
    var draft: ChannelDraft
    private(set) var isSaving = false
    private(set) var saveError: APIError?
    private(set) var didSave = false

    @ObservationIgnored private let client: APIClient

    init(channel: Channel, client: APIClient) {
        self.original = channel
        self.draft = ChannelDraft(channel: channel)
        self.client = client
    }

    var changes: ChannelChanges {
        draft.changes(against: original)
    }

    /// 进入编辑页时的颜色索引；颜色只存本地，因此不进入 ChannelChanges。
    var initialColorIndex: Int?
    /// 当前选中的颜色索引，由编辑页写入。
    var currentColorIndex: Int?

    /// 只有颜色变化时也应允许「保存」。
    var hasColorChange: Bool {
        guard let initialColorIndex, let currentColorIndex else { return false }
        return initialColorIndex != currentColorIndex
    }

    var hasChanges: Bool { !changes.isEmpty || hasColorChange }

    /// 频道正在运行时服务端返回 409 busy：全部输入保留，只提示原因。
    var isBlockedByRunning: Bool {
        if case .busy = saveError { return true }
        return false
    }

    func save() async -> Channel? {
        guard hasChanges, !isSaving else { return nil }
        isSaving = true
        saveError = nil
        didSave = false
        defer { isSaving = false }

        // 只有颜色变化时无需请求服务端，颜色已在本地保存。
        guard !changes.isEmpty else {
            initialColorIndex = currentColorIndex
            didSave = true
            return original
        }

        do {
            let updated = try await client.patchChannel(id: original.id, changes: changes)
            initialColorIndex = currentColorIndex
            didSave = true
            return updated
        } catch let apiError as APIError {
            saveError = apiError
            return nil
        } catch {
            saveError = .transport(error.localizedDescription)
            return nil
        }
    }
}
