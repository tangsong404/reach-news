import Foundation
import Observation

// MARK: - 频道列表
//
// enabled 开关即时生效、失败回滚；运行状态只对可见行轮询。

@MainActor
@Observable
final class ChannelStore {
    private(set) var channels: [Channel] = []
    private(set) var latestRuns: [String: Run] = [:]
    private(set) var isLoading = false
    private(set) var error: APIError?
    /// 正在提交 enabled 变更的频道，用于禁用重复点击。
    private(set) var pendingChannelIDs: Set<String> = []

    /// 当前可见的频道 ID，由视图上报；轮询只作用于这些行。
    private(set) var visibleChannelIDs: Set<String> = []

    /// 新建频道用的模板与连接器（仅创建流程需要）。
    private(set) var presets: [ChannelPreset] = []
    private(set) var connectors: [Connector] = []
    private(set) var isCreating = false
    private(set) var createError: APIError?

    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    init(client: APIClient) {
        self.client = client
    }

    // MARK: 派生状态

    var isEmpty: Bool { !isLoading && channels.isEmpty && error == nil }

    func channel(id: String) -> Channel? {
        channels.first { $0.id == id }
    }

    func latestRun(for channelID: String) -> Run? {
        latestRuns[channelID]
    }

    // MARK: 加载

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        var cursor: String?
        var collected: [Channel] = []
        var rounds = 0
        do {
            repeat {
                let page = try await client.channels(cursor: cursor, limit: Pagination.maxLimit)
                collected.append(contentsOf: page.items)
                cursor = page.nextCursor
                rounds += 1
            } while cursor != nil && rounds < 20
            // preset 频道归管理员，普通用户列表不展示（但仍会参与调度）。
            channels = collected.filter { $0.kind.isUserVisible }
            await refreshVisibleRuns()
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .transport(error.localizedDescription)
        }
    }

    // MARK: 开关

    /// 乐观切换：先本地翻转，失败回滚并保留原因。
    func setEnabled(_ enabled: Bool, for channelID: String) async {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else { return }
        let original = channels[index].enabled

        channels[index].enabled = enabled
        pendingChannelIDs.insert(channelID)
        error = nil
        defer { pendingChannelIDs.remove(channelID) }

        do {
            let updated = try await client.patchChannel(
                id: channelID,
                changes: ChannelChanges(enabled: enabled)
            )
            if let currentIndex = channels.firstIndex(where: { $0.id == channelID }) {
                channels[currentIndex] = updated
            }
        } catch let apiError as APIError {
            if let currentIndex = channels.firstIndex(where: { $0.id == channelID }) {
                channels[currentIndex].enabled = original
            }
            error = apiError
        } catch {
            if let currentIndex = channels.firstIndex(where: { $0.id == channelID }) {
                channels[currentIndex].enabled = original
            }
            self.error = .transport(error.localizedDescription)
        }
    }

    /// 创建流程所需的数据。连接器是必需的（否则建出的频道跑起来必 missed）。
    func loadCreationOptions() async {
        createError = nil
        do {
            async let presetList = client.presets()
            async let connectorList = client.connectors()
            // 预设只是可选的模板，失败不应阻止直接新建。
            presets = (try? await presetList) ?? []
            connectors = try await connectorList
        } catch let apiError as APIError {
            createError = apiError
        } catch {
            createError = .transport(error.localizedDescription)
        }
    }

    /// 直接新建频道（不依赖预设）。
    func create(
        name: String,
        prompt: String,
        tone: String,
        schedule: Schedule,
        connectorIDs: [String]
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
                connectorIDs: connectorIDs
            )
            if created.kind.isUserVisible {
                channels.insert(created, at: 0)
            }
            return created
        } catch let apiError as APIError {
            createError = apiError
            return nil
        } catch {
            createError = .transport(error.localizedDescription)
            return nil
        }
    }

    /// 从预设实例化一个自己的频道。
    func instantiate(presetID: String) async -> Channel? {
        guard !isCreating else { return nil }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            let created = try await client.instantiatePreset(id: presetID)
            if created.kind.isUserVisible {
                channels.insert(created, at: 0)
            }
            return created
        } catch let apiError as APIError {
            createError = apiError
            return nil
        } catch {
            createError = .transport(error.localizedDescription)
            return nil
        }
    }

    /// 软删除频道。
    /// - 成功：从列表移除。
    /// - 404（别人的或已删除）：按已删除处理，同样移除。
    /// - 409（有运行在跑）：不删除，返回失败原因。
    @discardableResult
    func delete(_ channelID: String) async -> Bool {
        createError = nil
        do {
            _ = try await client.deleteChannel(id: channelID)
            channels.removeAll { $0.id == channelID }
            return true
        } catch let apiError as APIError {
            if apiError == .notFound {
                // 目标已不存在，本地也应当移除。
                channels.removeAll { $0.id == channelID }
                return true
            }
            createError = apiError
            return false
        } catch {
            createError = .transport(error.localizedDescription)
            return false
        }
    }

    func replace(_ channel: Channel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[index] = channel
        } else {
            channels.append(channel)
        }
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
