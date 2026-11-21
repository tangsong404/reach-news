import Foundation

// MARK: - 分页参数
//
// 实测规则：limit 缺失/0/非数字 → 20，负数 → 1，>100 → 100。
// 客户端从不传负值或 0，也从不缓存负 cursor。

enum Pagination {
    static let defaultLimit = 20
    static let maxLimit = 100
    static let minLimit = 1

    /// 归一化客户端要发送的 limit。
    static func sanitizedLimit(_ requested: Int) -> Int {
        guard requested > 0 else { return defaultLimit }
        return min(requested, maxLimit)
    }

    /// 归一化服务端返回的 cursor：负值与非整数字符串一律丢弃。
    static func sanitizedCursor(_ raw: String?) -> String? {
        guard let raw, let value = Int(raw), value >= 0 else { return nil }
        return String(value)
    }

    /// 构造 query 项；cursor 不合规时不带该参数。
    static func queryItems(cursor: String?, limit: Int) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(sanitizedLimit(limit)))]
        if let cursor = sanitizedCursor(cursor), cursor != "0" {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return items
    }
}

// MARK: - 轮询基线
//
// ADR 0003：只持久化 lastSeenAt 这一个时间戳，与内容严格分开。
// 推进时取响应中最大的 created_at，不用本地时间（避免时钟偏差吞掉内容）。

enum PollingBaseline {
    static func next(baseline: Date?, payload: CursorPayload) -> Date? {
        guard let newest = payload.latestBriefAt else { return baseline }
        guard let baseline else { return newest }
        return max(baseline, newest)
    }

    /// 无历史基线时回落到 1970 年全量。
    static func sinceString(_ baseline: Date?) -> String {
        let date = baseline ?? Date(timeIntervalSince1970: 0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - 日报流筛选

enum FeedTimeFilter: Equatable, Hashable, CaseIterable, Identifiable {
    case all
    case thisWeek
    case thisMonth
    case lastThreeMonths
    case custom

    var id: String { labelKey }

    var labelKey: String {
        switch self {
        case .all: return "filter.time.all"
        case .thisWeek: return "filter.time.week"
        case .thisMonth: return "filter.time.month"
        case .lastThreeMonths: return "filter.time.quarter"
        case .custom: return "filter.time.custom"
        }
    }

    var isCustom: Bool { self == .custom }
}

struct FeedFilter: Equatable {
    var time: FeedTimeFilter = .all
    var startDate: Date?
    var endDate: Date?
    var channelIDs: Set<String> = []

    var isActive: Bool {
        time != .all || !channelIDs.isEmpty
    }

    /// 筛选按钮上的已应用维度计数：时间算一个维度，频道多选算一个维度。
    var activeDimensionCount: Int {
        var count = 0
        if time != .all { count += 1 }
        if !channelIDs.isEmpty { count += 1 }
        return count
    }

    var dateRange: ClosedRange<Date>? {
        resolvedRange(now: Date())
    }

    /// 解析时间预设为具体区间；自定义范围缺任一端时不构成区间。
    func resolvedRange(now: Date) -> ClosedRange<Date>? {
        let calendar = Calendar.shanghai
        switch time {
        case .all:
            return nil
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
            return interval.start...now
        case .thisMonth:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return nil }
            return interval.start...now
        case .lastThreeMonths:
            guard let start = calendar.date(byAdding: .month, value: -3, to: now) else { return nil }
            return start...now
        case .custom:
            guard let start = startDate, let end = endDate else { return nil }
            // 自定义范围按整天解释：起点取当天零点，终点取当天结束。
            let lowerDay = calendar.startOfDay(for: min(start, end))
            let upperDay = calendar.startOfDay(for: max(start, end))
            guard let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) else { return nil }
            return lowerDay...upper.addingTimeInterval(-0.001)
        }
    }

    /// 一期日报是否落在当前筛选内。
    func matches(_ brief: Brief) -> Bool {
        if !channelIDs.isEmpty && !channelIDs.contains(brief.channelID) {
            return false
        }
        if let range = dateRange {
            return range.contains(brief.createdAt)
        }
        return true
    }

    /// 需要继续向后加载的边界：区间起点。已覆盖到该点即停止。
    var requiredLowerBound: Date? {
        dateRange?.lowerBound
    }
}

// MARK: - 日报流逻辑

enum BriefFeed {
    /// 按 ID 去重并按 createdAt 倒序；已有项保持原位置，新项插入。
    static func merge(existing: [Brief], incoming: [Brief]) -> [Brief] {
        guard !incoming.isEmpty else { return existing }
        var seen = Set(existing.map(\.id))
        var merged = existing
        for brief in incoming where seen.insert(brief.id).inserted {
            merged.append(brief)
        }
        return merged.sorted { $0.createdAt > $1.createdAt }
    }

    /// 按日期分组，保持倒序；组键为该日零点（Asia/Shanghai）。
    static func groupedByDay(_ briefs: [Brief]) -> [(day: Date, briefs: [Brief])] {
        let calendar = Calendar.shanghai
        var order: [Date] = []
        var buckets: [Date: [Brief]] = [:]
        for brief in briefs {
            let day = calendar.startOfDay(for: brief.createdAt)
            if buckets[day] == nil {
                order.append(day)
                buckets[day] = []
            }
            buckets[day]?.append(brief)
        }
        return order
            .sorted(by: >)
            .map { ($0, buckets[$0] ?? []) }
    }

    /// 搜索：按标题过滤。
    static func search(_ briefs: [Brief], query: String) -> [Brief] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return briefs }
        return briefs.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    /// 已加载内容是否已覆盖筛选所需的下界。
    static func coversLowerBound(_ briefs: [Brief], bound: Date?) -> Bool {
        guard let bound else { return true }
        guard let oldest = briefs.map(\.createdAt).min() else { return true }
        return oldest <= bound
    }

    /// 「显示 N 期」中的 N。
    static func filtered(_ briefs: [Brief], query: String, filter: FeedFilter) -> [Brief] {
        search(briefs, query: query).filter(filter.matches)
    }
}
