import Foundation

// MARK: - JSON 解码基础
//
// 服务端全部时间是 UTC ISO 8601 带毫秒，形如 2026-11-20T02:01:50.774Z。
// 这里一次解析成 Date；UI 展示时才转 Asia/Shanghai。

enum JSONDate {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return withFractional.date(from: raw) ?? withoutFractional.date(from: raw)
    }
}

// MARK: - 宽松布尔
//
// `/cursor` 的 `enabled` 是整数 1/0，其余端点是 JSON 布尔。

struct FlexibleBool: Decodable, Equatable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int != 0
        } else if let string = try? container.decode(String.self) {
            value = ["1", "true", "yes"].contains(string.lowercased())
        } else {
            value = false
        }
    }

    init(_ value: Bool) {
        self.value = value
    }
}

// MARK: - 错误信封

struct ErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }

    let error: Payload

    var normalized: APIError {
        switch APIErrorCode.parse(error.code) {
        case .unauthorized: return .unauthorized
        case .tooManyAttempts: return .tooManyAttempts
        case .invalidConnector: return .invalidConnector(error.message)
        case .notFound: return .notFound
        case .invalidInput: return .invalidInput(error.message)
        case .busy: return .busy(error.message)
        case .badRequest: return .badRequest(error.message)
        case .internalError: return .server(error.message)
        case .unknown: return .server(error.message)
        }
    }
}

// MARK: - 分页信封

struct PageEnvelope<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

// MARK: - 频道

struct ChannelConnectorDTO: Decodable {
    let id: String
    let name: String?
    let kind: String?
    let removed: Bool?

    func toDomain() -> ChannelConnector {
        ChannelConnector(id: id, name: name, kind: kind, removed: removed ?? false)
    }
}

struct ChannelDTO: Decodable {
    let id: String
    let name: String
    let prompt: String?
    let tone: String?
    let schedule: [String: [String]]?
    let enabled: FlexibleBool?
    let connectorIds: [String]?
    let connectors: [ChannelConnectorDTO]?
    let lastBriefAt: String?
    let kind: String?
    let createdAt: String?
    let updatedAt: String?

    func toDomain() -> Channel {
        Channel(
            id: id,
            name: name,
            prompt: prompt ?? "",
            tone: tone ?? "",
            schedule: Schedule(timesByWeekday: schedule ?? [:]),
            enabled: enabled?.value ?? false,
            connectorIDs: connectorIds ?? [],
            connectors: (connectors ?? []).map { $0.toDomain() },
            lastBriefAt: JSONDate.parse(lastBriefAt),
            kind: ChannelKind(apiValue: kind),
            createdAt: JSONDate.parse(createdAt) ?? .distantPast,
            updatedAt: JSONDate.parse(updatedAt) ?? .distantPast
        )
    }
}

// MARK: - 日报

struct BriefSectionDTO: Decodable {
    struct EntryDTO: Decodable {
        let title: String
        let summary: String?
        let itemIds: [String]?
    }

    let title: String
    let items: [EntryDTO]?

    func toDomain() -> BriefSection {
        BriefSection(
            title: title,
            entries: (items ?? []).map {
                Entry(title: $0.title, summary: $0.summary ?? "", materialIDs: $0.itemIds ?? [])
            }
        )
    }
}

struct BriefDTO: Decodable {
    let id: String
    let channelId: String
    let title: String
    let sections: [BriefSectionDTO]?
    let memorySummary: String?
    let createdAt: String
    /// 仅全量日报端点返回，用于免去回查频道。
    let channelName: String?
    let channelKind: String?

    func toDomain() -> Brief {
        Brief(
            id: id,
            channelID: channelId,
            title: title,
            sections: (sections ?? []).map { $0.toDomain() },
            memorySummary: memorySummary ?? "",
            createdAt: JSONDate.parse(createdAt) ?? .distantPast,
            channelName: channelName,
            channelKind: channelKind.map(ChannelKind.init(apiValue:))
        )
    }
}

// MARK: - 连接器与预设

struct ConnectorDTO: Decodable {
    let id: String
    let name: String
    let kind: String?

    func toDomain() -> Connector {
        Connector(id: id, name: name, kind: kind ?? "")
    }
}

struct PresetDTO: Decodable {
    let id: String
    let name: String
    let prompt: String?
    let tone: String?
    let schedule: [String: [String]]?
    let connectorIds: [String]?

    func toDomain() -> ChannelPreset {
        ChannelPreset(
            id: id,
            name: name,
            prompt: prompt ?? "",
            tone: tone ?? "",
            schedule: Schedule(timesByWeekday: schedule ?? [:]),
            connectorIDs: connectorIds ?? []
        )
    }
}

// MARK: - 素材

struct MaterialDTO: Decodable {
    struct MetadataDTO: Decodable {
        let source: String?
        let rawFormat: String?
    }

    let id: String
    let title: String
    let url: String
    let publishedAt: String?
    let metadata: MetadataDTO?
    let content: String?

    func toDomain() -> Material? {
        guard let parsed = URL(string: url), parsed.scheme != nil else { return nil }
        return Material(
            id: id,
            title: title,
            url: parsed,
            publishedAt: JSONDate.parse(publishedAt),
            sourceLabel: metadata?.source,
            content: content ?? ""
        )
    }
}

// MARK: - 运行

struct RunDTO: Decodable {
    let id: String
    let channelId: String?
    let state: String?
    let trigger: String?
    let startedAt: String?
    let finishedAt: String?
    let missedReason: String?
    let createdAt: String?

    func toDomain() -> Run {
        Run(
            id: id,
            channelID: channelId,
            state: RunState(apiValue: state),
            trigger: RunTrigger.parse(trigger),
            startedAt: JSONDate.parse(startedAt),
            finishedAt: JSONDate.parse(finishedAt),
            missedReason: MissedReason.parse(missedReason),
            createdAt: JSONDate.parse(createdAt) ?? .distantPast
        )
    }
}

// MARK: - 追问
//
// 历史字段是 snake_case，与其余端点不一致，在 DTO 层转换。

struct AskTurnDTO: Decodable {
    let id: String
    let role: String?
    let message: String
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case message
        case createdAt
        case createdAtLegacy = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        message = try c.decode(String.self, forKey: .message)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decode(String.self, forKey: .createdAtLegacy)
    }

    func toDomain() -> AskTurn {
        AskTurn(
            id: id,
            role: AskRole.parse(role),
            message: message,
            createdAt: JSONDate.parse(createdAt) ?? .distantPast
        )
    }
}

struct AskResponseDTO: Decodable {
    let message: String?
    let answer: String
    /// 这条回答依据的素材 ID；服务端从本期 sections 汇总去重。
    let citedItemIds: [String]?
    /// 服务端明确标注：确定性应答，未接 LLM。
    let deterministic: Bool?
}

// MARK: - 轮询
//
// 后端已统一为 camelCase + 布尔。仍兼容旧的 snake_case 与整数 enabled，
// 避免服务端灰度期间解析失败。

struct CursorBriefDTO: Decodable {
    let id: String
    let channelId: String
    let title: String
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case channelId
        case channelIdLegacy = "channel_id"
        case title
        case createdAt
        case createdAtLegacy = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
            ?? c.decode(String.self, forKey: .channelIdLegacy)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decode(String.self, forKey: .createdAtLegacy)
    }

    func toDomain() -> CursorBrief {
        CursorBrief(
            id: id,
            channelID: channelId,
            title: title,
            createdAt: JSONDate.parse(createdAt) ?? .distantPast
        )
    }
}

struct CursorChannelDTO: Decodable {
    let id: String
    let name: String
    let enabled: FlexibleBool?
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case enabled
        case updatedAt
        case updatedAtLegacy = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(FlexibleBool.self, forKey: .enabled)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? c.decode(String.self, forKey: .updatedAtLegacy)
    }

    func toDomain() -> CursorChannel {
        CursorChannel(
            id: id,
            name: name,
            enabled: enabled?.value ?? false,
            updatedAt: JSONDate.parse(updatedAt) ?? .distantPast
        )
    }
}

struct CursorDTO: Decodable {
    let briefs: [CursorBriefDTO]?
    let channels: [CursorChannelDTO]?

    func toDomain() -> CursorPayload {
        CursorPayload(
            briefs: (briefs ?? []).map { $0.toDomain() },
            channels: (channels ?? []).map { $0.toDomain() }
        )
    }
}

// MARK: - 登录

struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct LoginUserDTO: Decodable {
    let id: String
    let name: String
}

struct LoginResponseDTO: Decodable {
    let token: String
    let expiresAt: String?
    let user: LoginUserDTO?

    func session() throws -> AuthSession {
        guard let expires = JSONDate.parse(expiresAt) else {
            throw APIError.decodingFailed
        }
        return AuthSession(token: token, expiresAt: expires, userName: user?.name ?? "")
    }
}

struct LogoutResponseDTO: Decodable {
    let ok: Bool?
}

struct DeleteChannelResponseDTO: Decodable {
    let id: String
    let deleted: Bool?
}

// MARK: - 服务端设置

struct SettingsDTO: Decodable {
    let timeZone: String?
}

// MARK: - 健康检查

struct HealthDTO: Decodable {
    let ok: Bool
    let service: String?
    let time: String?
}

// MARK: - 请求体

struct AskRequestBody: Encodable {
    let message: String
}

struct CreateChannelBody: Encodable {
    let name: String
    let prompt: String
    let tone: String
    let schedule: [String: [String]]
    let connectorIds: [String]
}

struct ChannelPatchBody: Encodable {
    let name: String?
    let prompt: String?
    let tone: String?
    let schedule: [String: [String]]?
    let enabled: Bool?
    let connectorIds: [String]?

    init(changes: ChannelChanges) {
        name = changes.name
        prompt = changes.prompt
        tone = changes.tone
        enabled = changes.enabled
        connectorIds = changes.connectorIDs
        if let schedule = changes.schedule {
            self.schedule = Dictionary(
                uniqueKeysWithValues: Schedule.weekdays.compactMap { weekday in
                    let times = schedule.times(for: weekday)
                    return times.isEmpty ? nil : (weekday.key, times)
                }
            )
        } else {
            self.schedule = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case prompt
        case tone
        case schedule
        case enabled
        case connectorIds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(tone, forKey: .tone)
        try container.encodeIfPresent(schedule, forKey: .schedule)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(connectorIds, forKey: .connectorIds)
    }
}
