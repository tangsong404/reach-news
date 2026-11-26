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
        case .presetsRemoved: return .removed(error.message)
        case .notPublished: return .notPublished(error.message)
        case .ownChannel: return .ownChannel(error.message)
        case .subscriberReadOnly: return .subscriberReadOnly(error.message)
        case .channelQuotaExceeded: return .channelQuotaExceeded(error.message)
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
    /// 订阅模型新增：只增不减，字段形状向后兼容。
    let published: FlexibleBool?
    let owner: String?
    let subscribed: FlexibleBool?
    let subscriptionColor: String?
    let subscriptionId: String?
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
            published: published?.value ?? false,
            owner: ChannelOwner(apiValue: owner),
            subscribed: subscribed?.value ?? false,
            // 服务端未订阅时为 null，订阅时未给颜色为空字符串；两者都交给上层按「未设置」处理。
            subscriptionColor: subscriptionColor,
            subscriptionID: subscriptionId,
            createdAt: JSONDate.parse(createdAt) ?? .distantPast,
            updatedAt: JSONDate.parse(updatedAt) ?? .distantPast
        )
    }
}

/// 订阅成功响应：`{ id, channelId, color, createdAt, subscribed }`。
struct SubscriptionDTO: Decodable {
    let id: String
    let channelId: String
    let color: String?
    let createdAt: String?
    let subscribed: FlexibleBool?
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

// MARK: - 日报正文

/// 正文片段：`{ type, text, url?, itemId? }`。
struct BriefSegmentDTO: Decodable {
    let type: String?
    let text: String?
    let url: String?
    let itemId: String?

    /// 归一化：只有 type 为 link 且 url 合法时才建链接，其余一律按纯文字，保证内容不丢。
    func toDomain() -> BriefSegment? {
        let content = text ?? ""
        guard !content.isEmpty else { return nil }
        guard (type ?? "text") == "link",
              let raw = url,
              let parsed = URL(string: raw),
              parsed.scheme != nil else {
            return .text(content)
        }
        return .link(text: content, url: parsed, itemID: itemId)
    }
}

struct BriefParagraphDTO: Decodable {
    let segments: [BriefSegmentDTO]?

    func toDomain() -> BriefParagraph? {
        let parsed = (segments ?? []).compactMap { $0.toDomain() }
        return parsed.isEmpty ? nil : BriefParagraph(segments: parsed)
    }
}

/// 正文：`{ paragraphs: [{ segments: [...] }] }`。
/// null、字段缺失、空数组都归一化为 nil，走同一条「无可读正文」路径。
struct BriefBodyDTO: Decodable {
    let paragraphs: [BriefParagraphDTO]?

    func toDomain() -> BriefBody? {
        let parsed = (paragraphs ?? []).compactMap { $0.toDomain() }
        guard !parsed.isEmpty else { return nil }
        let body = BriefBody(paragraphs: parsed)
        return body.isEmpty ? nil : body
    }
}

struct BriefDTO: Decodable {
    let id: String
    let channelId: String
    let title: String
    let summary: String?
    let body: BriefBodyDTO?
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
            summary: summary,
            body: body?.toDomain(),
            sections: (sections ?? []).map { $0.toDomain() },
            memorySummary: memorySummary ?? "",
            createdAt: JSONDate.parse(createdAt) ?? .distantPast,
            channelName: channelName,
            channelKind: channelKind.map(ChannelKind.init(apiValue:))
        )
    }
}

// MARK: - 连接器

struct ConnectorDTO: Decodable {
    let id: String
    let name: String
    let kind: String?

    func toDomain() -> Connector {
        Connector(id: id, name: name, kind: kind ?? "")
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
    /// 未填写时为 nil；不要在这里塞空串，界面需要区分「没有邮箱」与「空字符串」。
    let email: String?
    /// 服务端原样返回的档位，例如 free / ultra / admin。
    let tier: String?
    /// 形如 `/api/v1/users/xxx/avatar`；nil 表示没有头像。
    let avatarUrl: String?

    func toDomain() -> UserProfile {
        UserProfile(
            id: id,
            name: name,
            email: email,
            tier: tier ?? "",
            avatarURLPath: avatarUrl,
            channelCount: nil
        )
    }
}

struct CapabilitiesDTO: Decodable {
    let tier: String?
    let ask: Bool?
    let briefImages: Bool?
    /// nil 表示不限。
    let channelLimit: Int?

    func toDomain() -> UserCapabilities {
        UserCapabilities(
            tier: tier ?? "",
            ask: ask ?? true,
            briefImages: briefImages ?? false,
            channelLimit: channelLimit
        )
    }
}

/// 登录与注册共用同一响应形状：注册成功后不需要再调一次登录。
struct LoginResponseDTO: Decodable {
    let token: String
    let expiresAt: String?
    let user: LoginUserDTO?
    let capabilities: CapabilitiesDTO?

    func session() throws -> AuthSession {
        guard let expires = JSONDate.parse(expiresAt) else {
            throw APIError.decodingFailed
        }
        return AuthSession(token: token, expiresAt: expires, userName: user?.name ?? "")
    }

    func profile() -> UserProfile? { user?.toDomain() }

    func capabilitySet() -> UserCapabilities { capabilities?.toDomain() ?? .unknown }
}

// MARK: - 注册

struct RegisterRequest: Encodable {
    let nickname: String
    let email: String
    let password: String
    let passwordConfirm: String
    /// 开放注册模式下可以不填；由服务端配置决定是否必填。
    let inviteCode: String?
    /// hCaptcha 已配置时必填。
    let captchaToken: String?
    /// SMTP 已配置时必填。
    let emailCode: String?

    private enum CodingKeys: String, CodingKey {
        case nickname, email, password, passwordConfirm, inviteCode, captchaToken, emailCode
    }

    /// 可选扩展字段为 nil 时**不编码**，而不是编码成 null：
    /// 服务端用「字段是否存在」区分开放注册与带验证的请求。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(email, forKey: .email)
        try container.encode(password, forKey: .password)
        try container.encode(passwordConfirm, forKey: .passwordConfirm)
        try container.encodeIfPresent(inviteCode, forKey: .inviteCode)
        try container.encodeIfPresent(captchaToken, forKey: .captchaToken)
        try container.encodeIfPresent(emailCode, forKey: .emailCode)
    }
}

// MARK: - 当前用户

struct MeResponseDTO: Decodable {
    let id: String
    let name: String
    let email: String?
    let tier: String?
    let avatarUrl: String?
    let createdAt: String?
    let channelCount: Int?
    let capabilities: CapabilitiesDTO?

    func profile() -> UserProfile {
        UserProfile(
            id: id,
            name: name,
            email: email,
            tier: tier ?? "",
            avatarURLPath: avatarUrl,
            channelCount: channelCount
        )
    }
}

// MARK: - 改密码

struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
    let newPasswordConfirm: String
    /// 必填（2026-11-26 起）：先调 /auth/email-code（purpose=change-password）。
    /// 只有当前密码不够——否则任何拿到已登录设备的人都能把机主锁在外面。
    let emailCode: String
}

struct OKResponseDTO: Decodable {
    let ok: Bool?
}

// MARK: - 人机验证配置

struct CaptchaConfigDTO: Decodable {
    /// 服务端是否已启用（site key 与 secret 都配好才算）。
    let enabled: Bool?
    /// enabled 为 false 时为 nil。
    let siteKey: String?
}

// MARK: - 邮箱验证码

struct EmailCodeRequest: Encodable {
    let email: String
    /// `register` 或 `reset-password`
    let purpose: String
    /// hCaptcha 已配置时必填。
    let captchaToken: String?
}

/// 请求验证码的失败：保留 code / message / retryAfterSeconds。
struct EmailCodeFailure: Equatable {
    let code: String
    let message: String
    /// 429 时的冷却秒数，用于界面倒计时。
    let retryAfterSeconds: Int?
    let statusCode: Int

    init(code: String, message: String, retryAfterSeconds: Int?, statusCode: Int) {
        self.code = code
        self.message = message
        self.retryAfterSeconds = retryAfterSeconds
        self.statusCode = statusCode
    }

    init(from data: Data, statusCode: Int) {
        self.statusCode = statusCode
        let decoded = try? JSONDecoder().decode(EmailCodeFailureEnvelope.self, from: data)
        self.code = decoded?.error.code ?? "unknown"
        self.message = decoded?.error.message ?? ""
        self.retryAfterSeconds = decoded?.retryAfterSeconds
    }

    /// 本地前置校验失败（邮箱为空）时使用，避免走一次必然失败的请求。
    static let emptyEmail = EmailCodeFailure(code: "email_required", message: "", retryAfterSeconds: nil, statusCode: 0)

    /// 服务端未配置邮件服务：不是用户操作错误，应提示联系管理员。
    var isMailNotConfigured: Bool { code == "mail_not_configured" }
    var isCaptchaRequired: Bool { code == "captcha_required" || code == "captcha_failed" }
}

struct EmailCodeFailureEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }
    let error: Payload
    let retryAfterSeconds: Int?
}

enum EmailCodeOutcome {
    case sent
    case rejected(EmailCodeFailure)
}

// MARK: - 头像上传

struct AvatarUploadResponseDTO: Decodable {
    let avatarUrl: String?
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

// MARK: - 订阅请求体
//
// 订阅体只有 color 一个字段（≤32 字符）；fork 的 name 可选。

struct SubscribeBody: Encodable {
    let color: String
}

struct SubscriptionColorBody: Encodable {
    let color: String
}

struct ForkChannelBody: Encodable {
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

/// 取消订阅响应：`{ channelId, subscribed: false }`。
struct UnsubscribeResponseDTO: Decodable {
    let channelId: String
    let subscribed: FlexibleBool?
}
