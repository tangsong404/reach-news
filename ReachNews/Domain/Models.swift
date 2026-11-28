import Foundation

// MARK: - 采集时间表
//
// 周一至周日各可配零到多个 HH:MM；未配置的星期不出现。所有时刻按 Asia/Shanghai 解释。

struct Schedule: Equatable, Hashable {
    struct Weekday: Equatable, Hashable, Identifiable, CaseIterable {
        let key: String
        let calendarIndex: Int
        let symbolKey: String
        /// 时间表编辑器里的短名，避免英文长名换行断字。
        let shortKey: String

        var id: String { key }

        static var allCases: [Weekday] { all }

        static let all: [Weekday] = [
            Weekday(key: "mon", calendarIndex: 2, symbolKey: "weekday.mon", shortKey: "weekday.mon.short"),
            Weekday(key: "tue", calendarIndex: 3, symbolKey: "weekday.tue", shortKey: "weekday.tue.short"),
            Weekday(key: "wed", calendarIndex: 4, symbolKey: "weekday.wed", shortKey: "weekday.wed.short"),
            Weekday(key: "thu", calendarIndex: 5, symbolKey: "weekday.thu", shortKey: "weekday.thu.short"),
            Weekday(key: "fri", calendarIndex: 6, symbolKey: "weekday.fri", shortKey: "weekday.fri.short"),
            Weekday(key: "sat", calendarIndex: 7, symbolKey: "weekday.sat", shortKey: "weekday.sat.short"),
            Weekday(key: "sun", calendarIndex: 1, symbolKey: "weekday.sun", shortKey: "weekday.sun.short")
        ]

        static func key(forCalendarIndex index: Int) -> String {
            all.first { $0.calendarIndex == index }?.key ?? "mon"
        }
    }

    /// 按周一…周日顺序保存每天的时刻，未配置的星期为空数组。
    private(set) var timesByWeekday: [String: [String]]

    static let weekdays: [Weekday] = Weekday.all

    init(timesByWeekday: [String: [String]] = [:]) {
        var sanitized: [String: [String]] = [:]
        for weekday in Schedule.weekdays {
            let times = timesByWeekday[weekday.key] ?? []
            sanitized[weekday.key] = Schedule.normalized(times)
        }
        self.timesByWeekday = sanitized
    }

    var isEmpty: Bool {
        timesByWeekday.values.allSatisfy(\.isEmpty)
    }

    func times(for weekday: Weekday) -> [String] {
        timesByWeekday[weekday.key] ?? []
    }

    func isEnabled(_ weekday: Weekday) -> Bool {
        !times(for: weekday).isEmpty
    }

    var activeWeekdays: [Weekday] {
        Schedule.weekdays.filter(isEnabled)
    }

    /// 全部时刻去重后按时间排序，供展示与「通常时刻」使用。
    var allTimes: [String] {
        Schedule.normalized(timesByWeekday.values.flatMap { $0 })
    }

    /// 闹钟式切换：把当前选中的时刻一次性应用到某个星期，或清空它。
    mutating func toggle(_ weekday: Weekday, at time: String) {
        if isEnabled(weekday) {
            timesByWeekday[weekday.key] = []
        } else {
            timesByWeekday[weekday.key] = Schedule.normalized([time])
        }
    }

    mutating func toggle(_ weekday: Weekday) {
        toggle(weekday, at: allTimes.first ?? "08:00")
    }

    /// 把一组星期设为同一个时刻（闹钟里改时间后的行为）。
    mutating func setTime(_ time: String, for weekdays: [Weekday]) {
        guard Schedule.isValid(time) else { return }
        for weekday in weekdays {
            timesByWeekday[weekday.key] = [time]
        }
    }

    /// 该时刻覆盖了哪些星期；用于闹钟式选择器的初始选中。
    func weekdays(at time: String) -> [Weekday] {
        Schedule.weekdays.filter { times(for: $0) == [time] }
    }

    /// 所有已配置时刻的合集（空表示尚未配置）。
    var configuredTimes: [String] { allTimes }

    /// 每个星期最多保留的触发时刻数（服务端限制）。
    static let maxTimesPerWeekday = 5

    mutating func addTime(_ time: String, to weekday: Weekday) {
        var times = times(for: weekday)
        guard !times.contains(time) else { return }
        guard times.count < Schedule.maxTimesPerWeekday else { return }
        times.append(time)
        timesByWeekday[weekday.key] = Schedule.normalized(times)
    }

    func canAddTime(to weekday: Weekday) -> Bool {
        times(for: weekday).count < Schedule.maxTimesPerWeekday
    }

    mutating func removeTime(_ time: String, from weekday: Weekday) {
        timesByWeekday[weekday.key] = times(for: weekday).filter { $0 != time }
    }

    private static func normalized(_ times: [String]) -> [String] {
        var seen = Set<String>()
        return times
            .filter { isValid($0) }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              parts[0].count == 2, parts[1].count == 2,
              (0...23).contains(hour), (0...59).contains(minute) else {
            return false
        }
        return true
    }
}

// MARK: - 会话凭证
//
// 后端以账号密码换 7 天会话凭证；本地保存 token 与过期时刻，
// 过期或收到 401 都应回到登录页，没有 refresh 接口。

struct AuthSession: Equatable {
    let token: String
    let expiresAt: Date
    let userName: String

    func isExpired(now: Date = Date()) -> Bool {
        expiresAt <= now
    }
}

// MARK: - 频道
//
// owner 决定可写性：订阅者只读，只有创建者能编辑、触发运行、删除。
// 订阅是「用户 × 频道」的关系，不产生独立频道条目。

/// Approved collection source. Unavailable bindings remain visible in channel responses.
struct CollectorSkill: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var description: String = ""
    var version: String = ""
    var available: Bool = false
    var reason: String? = nil
    var message: String? = nil
    var iconURLPath: String? = nil
}

struct CollectionStatus: Equatable, Hashable {
    var available: Bool
    var pausedReason: String? = nil
}

struct Channel: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var prompt: String
    var tone: String
    var schedule: Schedule
    var enabled: Bool
    var connectorIDs: [String]
    /// 服务端解析出的连接器详情；删掉 UUID 直显，直接用 name。
    var connectors: [ChannelConnector]
    var lastBriefAt: Date?
    var kind: ChannelKind
    var published: Bool = false
    var owner: ChannelOwner = .creator
    var subscribed: Bool = false
    /// 订阅者自选颜色；未订阅为 nil，订阅时未给颜色则可能是空字符串。
    var subscriptionColor: String? = nil
    var subscriptionID: String? = nil
    var createdAt: Date
    var updatedAt: Date
    var collectorSkillIDs: [String] = []
    var collectorSkills: [CollectorSkill] = []
    var collectionStatus: CollectionStatus? = nil

    /// 未配置连接器却处于启用状态 —— 运行必然错过（no-material）。
    var hasNoConnectors: Bool { collectorSkillIDs.isEmpty }

    var hasUsableCollectorSkills: Bool {
        collectionStatus?.available ?? (!collectorSkillIDs.isEmpty && collectorSkills.allSatisfy(\.available))
    }

    /// 需要提示「运行将不会产出日报」的情形。订阅频道不提示：连接器由创建者决定。
    var warnsAboutMissingConnectors: Bool {
        enabled && hasNoConnectors && owner.isCreator
    }

    // MARK: 可写性判定（唯一正确写法）
    //
    // 一律看 owner，不看 kind：kind 只区分「用户频道」与「跟踪」。

    /// 能 PATCH / 触发运行 / 删除。
    var canEdit: Bool { owner.isCreator }

    /// 能订阅：已公开、不是自己创建的、当前未订阅。
    var canSubscribe: Bool { published && !owner.isCreator && !subscribed }

    /// 能取消订阅。
    var canUnsubscribe: Bool { subscribed }

    /// 当前用户是否为该频道的订阅者（只读）。
    var isSubscription: Bool { owner == .subscriber && subscribed }

    /// 订阅色的有效值：空字符串与 nil 都按「未设置」处理。
    var effectiveSubscriptionColor: String? {
        guard let color = subscriptionColor?.trimmingCharacters(in: .whitespaces),
              !color.isEmpty else { return nil }
        return color
    }
}

// MARK: - 日报

struct BriefSection: Identifiable, Equatable, Hashable {
    let title: String
    let entries: [Entry]

    var id: String { title }
}

/// 日报分组内的一条聚合。字段名在 payload 里是 `items`，但它是条目，不是素材。
struct Entry: Identifiable, Equatable, Hashable {
    let title: String
    let summary: String
    let materialIDs: [String]

    var id: String { title + "|" + materialIDs.joined(separator: ",") }
}

struct Brief: Identifiable, Equatable, Hashable {
    let id: String
    let channelID: String
    let title: String
    /// 这一期给读者的描述，可为 nil（模型未产出时是正常状态）。
    var summary: String?
    /// 精写正文；为 nil 时读者端显示「本期无可读正文」。
    var body: BriefBody?
    let sections: [BriefSection]
    /// 运行记忆，供 Ask 与后续运行使用。**不在任何界面展示**：措辞不是写给读者的。
    let memorySummary: String
    let createdAt: Date
    /// 全量日报端点自带频道信息，避免为了渲染名称再回查频道。
    var channelName: String?
    var channelKind: ChannelKind?

    /// 有可读正文（body 非空且不是空白段落）。
    var hasReadableBody: Bool {
        guard let body else { return false }
        return !body.isEmpty
    }

    /// 列表与详情展示用的描述；空字符串与 nil 一视同仁。
    var displaySummary: String? {
        guard let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return nil }
        return summary
    }

    var entryCount: Int {
        sections.reduce(0) { $0 + $1.entries.count }
    }

    /// 素材数：本期全部条目的 materialIds 去重计数。
    var materialCount: Int {
        var ids = Set<String>()
        for section in sections {
            for entry in section.entries {
                ids.formUnion(entry.materialIDs)
            }
        }
        return ids.count
    }

    var allMaterialIDs: [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for section in sections {
            for entry in section.entries {
                for id in entry.materialIDs where seen.insert(id).inserted {
                    ordered.append(id)
                }
            }
        }
        return ordered
    }
}

// MARK: - 素材
//
// `content` 只解析不展示：RSS 是原始 XML，GitHub 是原始 JSON 字符串。

struct Material: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let url: URL
    let publishedAt: Date?
    let sourceLabel: String?
    let content: String

    var host: String {
        url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }

    /// 素材行左侧的两字母方块。
    var monogram: String {
        let name = host.split(separator: ".").first.map(String.init) ?? host
        let letters = name.prefix(2).uppercased()
        return letters.isEmpty ? "··" : String(letters)
    }
}

// MARK: - 连接器

struct Connector: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let kind: String
}

/// 频道内嵌的连接器条目。`name` 可能为 null（已从代码移除），此时提示失效而不是显示 UUID。
struct ChannelConnector: Identifiable, Equatable, Hashable {
    let id: String
    let name: String?
    let kind: String?
    let removed: Bool

    var displayName: String { name ?? id }
    var isUnavailable: Bool { removed || name == nil }
}

// MARK: - 运行

struct Run: Identifiable, Equatable, Hashable {
    let id: String
    let channelID: String?
    let state: RunState
    let trigger: RunTrigger
    let startedAt: Date?
    let finishedAt: Date?
    let missedReason: MissedReason?
    let createdAt: Date
}

// MARK: - 追问

struct AskTurn: Identifiable, Equatable, Hashable {
    let id: String
    let role: AskRole
    let message: String
    let createdAt: Date
}

/// 一次追问的结果：回答本体 + 它引用的素材。
/// 服务端当前是确定性应答，`isDeterministic` 明确标注这一点。
struct AskReply: Equatable {
    let turn: AskTurn
    let citedItemIDs: [String]
    let isDeterministic: Bool
}

// MARK: - 轮询

/// `/cursor` 返回的新增日报摘要（snake_case 已归一化）。
struct CursorBrief: Identifiable, Equatable, Hashable {
    let id: String
    let channelID: String
    let title: String
    let createdAt: Date
}

/// `/cursor` 返回的频道摘要。`enabled` 在远端是整数 1/0，此处已是 Bool。
struct CursorChannel: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let enabled: Bool
    let updatedAt: Date
}

struct CursorPayload: Equatable {
    let briefs: [CursorBrief]
    let channels: [CursorChannel]

    var latestBriefAt: Date? {
        briefs.map(\.createdAt).max()
    }
}

// MARK: - 分页

struct Page<Element> {
    let items: [Element]
    let nextCursor: String?
}

// MARK: - 频道编辑草稿
//
// 保存时只提交被改动的字段。

struct ChannelDraft: Equatable {
    var name: String
    var prompt: String
    var tone: String
    var schedule: Schedule
    var enabled: Bool
    var collectorSkillIDs: [String]
    /// Compatibility alias; never serialized as connectorIds.
    var connectorIDs: [String] {
        get { collectorSkillIDs }
        set { collectorSkillIDs = newValue }
    }

    init(channel: Channel) {
        name = channel.name
        prompt = channel.prompt
        tone = channel.tone
        schedule = channel.schedule
        enabled = channel.enabled
        collectorSkillIDs = channel.collectorSkillIDs
    }

    func changes(against channel: Channel) -> ChannelChanges {
        var changes = ChannelChanges()
        if name != channel.name { changes.name = name }
        if prompt != channel.prompt { changes.prompt = prompt }
        if tone != channel.tone { changes.tone = tone }
        if schedule != channel.schedule { changes.schedule = schedule }
        if enabled != channel.enabled { changes.enabled = enabled }
        // 连接器整体替换；顺序无关，按集合比较。
        if Set(collectorSkillIDs) != Set(channel.collectorSkillIDs) { changes.collectorSkillIDs = collectorSkillIDs }
        return changes
    }
}

/// 只包含需要提交的字段；序列化时省略未改动的键。
struct ChannelChanges: Equatable {
    var name: String?
    var prompt: String?
    var tone: String?
    var schedule: Schedule?
    var enabled: Bool?
    var collectorSkillIDs: [String]?
    var connectorIDs: [String]? {
        get { collectorSkillIDs }
        set { collectorSkillIDs = newValue }
    }

    init(name: String? = nil, prompt: String? = nil, tone: String? = nil,
         schedule: Schedule? = nil, enabled: Bool? = nil,
         collectorSkillIDs: [String]? = nil, connectorIDs: [String]? = nil) {
        self.name = name; self.prompt = prompt; self.tone = tone
        self.schedule = schedule; self.enabled = enabled
        self.collectorSkillIDs = collectorSkillIDs ?? connectorIDs
    }

    var isEmpty: Bool {
        name == nil && prompt == nil && tone == nil && schedule == nil
            && enabled == nil && collectorSkillIDs == nil
    }

    var changedFieldNames: [String] {
        var names: [String] = []
        if name != nil { names.append("name") }
        if prompt != nil { names.append("prompt") }
        if tone != nil { names.append("tone") }
        if schedule != nil { names.append("schedule") }
        if enabled != nil { names.append("enabled") }
        if collectorSkillIDs != nil { names.append("collectorSkillIds") }
        return names
    }
}


