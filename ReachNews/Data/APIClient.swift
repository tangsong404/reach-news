import Foundation

// MARK: - 传输协议
//
// APIClient 只依赖这个协议，测试可注入固定响应而不打网络。

protocol HTTPTransporting {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransporting {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("unexpected-response")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet,
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorCannotConnectToHost,
                     NSURLErrorCannotFindHost,
                     NSURLErrorTimedOut,
                     NSURLErrorDataNotAllowed:
                    throw APIError.offline
                default:
                    throw APIError.transport(nsError.localizedDescription)
                }
            }
            throw APIError.transport(error.localizedDescription)
        }
    }
}

extension APIError {
    /// 把底层传输错误归一化成 .offline 或 .transport。
    static func normalize(transportError error: Error) -> APIError {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .transport(error.localizedDescription)
        }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorTimedOut,
             NSURLErrorDataNotAllowed,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorCannotLoadFromNetwork:
            return .offline
        default:
            return .transport(nsError.localizedDescription)
        }
    }
}

// MARK: - 端点

enum Endpoint {
    case health
    case login
    case logout
    case channels(cursor: String?, limit: Int, discover: Bool)
    case createChannel
    case channel(id: String)
    case briefs(channelID: String, cursor: String?, limit: Int)
    case brief(id: String)
    case material(briefID: String, materialID: String)
    case runs(channelID: String, cursor: String?, limit: Int)
    case run(id: String)
    case askHistory(briefID: String, cursor: String?, limit: Int)
    case ask(briefID: String)
    case cursor(since: Date?)
    case allBriefs(cursor: String?, limit: Int)
    case connectors
    case collectorSkills(cursor: String?, limit: Int)
    case subscribe(channelID: String)
    case fork(channelID: String)
    case settings
    case register
    case me
    case mePassword
    case avatar
    case captchaConfig
    case emailCode
    case resetPassword

    var path: String {
        switch self {
        case .health:
            return "/health"
        case .login:
            return "/api/v1/login"
        case .logout:
            return "/api/v1/logout"
        case .channels, .createChannel:
            return "/api/v1/channels"
        case .channel(let id):
            return "/api/v1/channels/\(id)"
        case .briefs(let channelID, _, _):
            return "/api/v1/channels/\(channelID)/briefs"
        case .brief(let id):
            return "/api/v1/briefs/\(id)"
        case .material(let briefID, let materialID):
            return "/api/v1/briefs/\(briefID)/items/\(materialID)"
        case .runs(let channelID, _, _):
            return "/api/v1/channels/\(channelID)/runs"
        case .run(let id):
            return "/api/v1/runs/\(id)"
        case .askHistory(let briefID, _, _):
            return "/api/v1/briefs/\(briefID)/ask"
        case .ask(let briefID):
            return "/api/v1/briefs/\(briefID)/ask"
        case .cursor:
            return "/api/v1/cursor"
        case .allBriefs:
            return "/api/v1/briefs"
        case .connectors:
            return "/api/v1/connectors"
        case .collectorSkills:
            return "/api/v1/collector-skills"
        case .subscribe(let channelID):
            return "/api/v1/channels/\(channelID)/subscribe"
        case .fork(let channelID):
            return "/api/v1/channels/\(channelID)/fork"
        case .settings:
            return "/api/v1/settings"
        case .register:
            return "/api/v1/register"
        case .me:
            return "/api/v1/me"
        case .mePassword:
            return "/api/v1/me/password"
        case .avatar:
            return "/api/v1/me/avatar"
        case .captchaConfig:
            return "/api/v1/auth/captcha"
        case .emailCode:
            return "/api/v1/auth/email-code"
        case .resetPassword:
            return "/api/v1/auth/reset-password"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .channels(let cursor, let limit, let discover):
            var items = Pagination.queryItems(cursor: cursor, limit: limit)
            // discover 只接受 1 或 true；其他值等同于普通列表，因此只在这里显式加。
            if discover { items.append(URLQueryItem(name: "discover", value: "1")) }
            return items
        case .collectorSkills(let cursor, let limit):
            return Pagination.queryItems(cursor: cursor, limit: limit)
        case .askHistory(_, let cursor, let limit):
            return Pagination.queryItems(cursor: cursor, limit: limit)
        case .briefs(_, let cursor, let limit),
             .runs(_, let cursor, let limit),
             .allBriefs(let cursor, let limit):
            return Pagination.queryItems(cursor: cursor, limit: limit)
        case .cursor(let since):
            return [URLQueryItem(name: "since", value: PollingBaseline.sinceString(since))]
        case .health, .login, .logout, .createChannel, .channel, .brief, .material, .run, .ask,
             .connectors, .subscribe, .fork, .settings, .register, .me, .mePassword, .avatar,
             .captchaConfig, .emailCode, .resetPassword:
            return []
        }
    }

    var requiresAuthorization: Bool {
        switch self {
        case .health, .login, .register, .captchaConfig, .emailCode, .resetPassword: return false
        default: return true
        }
    }
}

// MARK: - API 客户端

final class APIClient {
    private let transport: HTTPTransporting
    private let credentials: CredentialProviding
    let baseURL: URL

    init(
        baseURL: URL,
        transport: HTTPTransporting = URLSessionTransport(),
        credentials: CredentialProviding
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.credentials = credentials
    }

    /// 复制成指向另一个基础地址的客户端；已有实例不变。
    func withBaseURL(_ url: URL) -> APIClient {
        APIClient(baseURL: url, transport: transport, credentials: credentials)
    }

    /// 复制成使用另一组凭证的客户端，用于写入前的临时验证。
    func withCredentials(_ credentials: CredentialProviding) -> APIClient {
        APIClient(baseURL: baseURL, transport: transport, credentials: credentials)
    }

    // MARK: 端点调用

    func health() async throws -> HealthDTO {
        try await get(Endpoint.health)
    }

    /// 账号密码换会话凭证。这是唯一无需凭证的写端点。
    func login(username: String, password: String) async throws -> AuthSession {
        let body = try JSONEncoder().encode(LoginRequest(username: username, password: password))
        do {
            let dto: LoginResponseDTO = try await send(Endpoint.login, method: "POST", body: body)
            return try dto.session()
        } catch let error as APIError {
            throw error
        }
    }

    /// 注册结果：成功直接带会话与资料，失败带服务端 code 与 message。
    enum RegisterOutcome {
        case success(AuthSession, UserProfile, UserCapabilities)
        case rejected(RegistrationError)
    }

    /// 邀请码注册（公开端点）。
    ///
    /// 单独实现而不复用 `send`：注册的 14 种错误码需要原样保留给界面做逐项提示，
    /// 折叠成通用 `APIError` 会丢掉「邀请码已被使用」这类可操作信息。
    func register(
        nickname: String,
        email: String,
        password: String,
        passwordConfirm: String,
        inviteCode: String?,
        captchaToken: String? = nil,
        emailCode: String? = nil
    ) async throws -> RegisterOutcome {
        let payload = RegisterRequest(
            nickname: nickname,
            email: email,
            password: password,
            passwordConfirm: passwordConfirm,
            inviteCode: inviteCode,
            captchaToken: captchaToken,
            emailCode: emailCode
        )
        let body = try JSONEncoder().encode(payload)
        let request = try makeRequest(Endpoint.register, method: "POST", body: body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.normalize(transportError: error)
        }

        guard (200..<300).contains(response.statusCode) else {
            // 服务端已给出中文 message；没有 message 时保留空串，由界面用本地兜底文案。
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                let code = envelope.error.code
                if !code.isEmpty {
                    return .rejected(RegistrationError(code: code, message: envelope.error.message))
                }
            }
            if response.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.server("HTTP \(response.statusCode)")
        }

        guard let dto = try? JSONDecoder().decode(LoginResponseDTO.self, from: data) else {
            throw APIError.decodingFailed
        }
        let session = try dto.session()
        guard let profile = dto.profile() else { throw APIError.decodingFailed }
        return .success(session, profile, dto.capabilitySet())
    }

    /// 当前用户资料。用于冷启动恢复会话后补齐头部所需字段。
    func me() async throws -> (UserProfile, UserCapabilities) {
        let dto: MeResponseDTO = try await get(Endpoint.me)
        return (dto.profile(), dto.capabilities?.toDomain() ?? .unknown)
    }

    /// 上传头像（multipart，字段名 avatar）。成功后返回可直接使用的头像地址。
    func uploadAvatar(imageData: Data, filename: String = "avatar.png", mimeType: String = "image/png") async throws -> String? {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")

        var request = try makeRequest(Endpoint.avatar, method: "POST", body: body)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.normalize(transportError: error)
        }

        guard (200..<300).contains(response.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw envelope.normalized
            }
            if response.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.server("HTTP \(response.statusCode)")
        }
        return (try? JSONDecoder().decode(AvatarUploadResponseDTO.self, from: data))?.avatarUrl
    }

    /// 改昵称。成功后返回最新资料，调用方直接用它刷新头部，不必再打 GET。
    func updateNickname(_ name: String) async throws -> (UserProfile, UserCapabilities) {
        let body = try JSONEncoder().encode(["name": name])
        let dto: MeResponseDTO = try await send(Endpoint.me, method: "PATCH", body: body)
        return (dto.profile(), dto.capabilities?.toDomain() ?? .unknown)
    }

    /// 改密码。成功后当前 token 仍有效（服务端只清其他设备会话），调用方不踢用户。
    ///
    /// 失败时区分「当前密码错」与其他错误：401 统一按旧密码错误处理。
    func changePassword(current: String, new: String, confirm: String, emailCode: String) async throws {
        let payload = ChangePasswordRequest(
            currentPassword: current,
            newPassword: new,
            newPasswordConfirm: confirm,
            emailCode: emailCode
        )
        let body = try JSONEncoder().encode(payload)
        let _: OKResponseDTO = try await send(Endpoint.mePassword, method: "POST", body: body)
    }

    /// 删除头像；幂等，本来没有头像也返回成功。
    func deleteAvatar() async throws -> String? {
        let request = try makeRequest(Endpoint.avatar, method: "DELETE", body: nil)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw envelope.normalized
            }
            throw APIError.server("HTTP \(response.statusCode)")
        }
        return (try? JSONDecoder().decode(AvatarUploadResponseDTO.self, from: data))?.avatarUrl
    }

    /// 人机验证配置：客户端必须先取它才知道要用哪个 site key。
    func captchaConfig() async throws -> CaptchaConfigDTO {
        try await get(Endpoint.captchaConfig)
    }

    /// 请求邮箱验证码。
    ///
    /// 不使用通用 `send`：429 需要保留 `retryAfterSeconds` 做倒计时，
    /// 503 `mail_not_configured` 也要原样告知用户（不是用户操作错误）。
    func requestEmailCode(email: String, purpose: String, captchaToken: String?) async throws -> EmailCodeOutcome {
        let payload = EmailCodeRequest(email: email, purpose: purpose, captchaToken: captchaToken)
        let body = try JSONEncoder().encode(payload)
        let request = try makeRequest(Endpoint.emailCode, method: "POST", body: body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.normalize(transportError: error)
        }

        guard (200..<300).contains(response.statusCode) else {
            return .rejected(EmailCodeFailure(from: data, statusCode: response.statusCode))
        }
        return .sent
    }

    /// 注销当前会话凭证；失败不阻碍本地清理。
    func logout() async throws {
        let _: LogoutResponseDTO = try await send(Endpoint.logout, method: "POST", body: nil)
    }

    /// 频道列表：默认是「我创建的 + 我订阅的」；`discover` 为 true 时列全部已公开频道。
    func channels(
        cursor: String? = nil,
        limit: Int = Pagination.defaultLimit,
        discover: Bool = false
    ) async throws -> Page<Channel> {
        let envelope: PageEnvelope<ChannelDTO> = try await get(
            Endpoint.channels(cursor: cursor, limit: limit, discover: discover)
        )
        return Page(items: envelope.items.map { $0.toDomain() },
                    nextCursor: Pagination.sanitizedCursor(envelope.nextCursor))
    }

    func channel(id: String) async throws -> Channel {
        let dto: ChannelDTO = try await get(Endpoint.channel(id: id))
        return dto.toDomain()
    }

    func briefs(channelID: String, cursor: String? = nil, limit: Int = Pagination.defaultLimit) async throws -> Page<Brief> {
        let envelope: PageEnvelope<BriefDTO> = try await get(
            Endpoint.briefs(channelID: channelID, cursor: cursor, limit: limit)
        )
        return Page(items: envelope.items.map { $0.toDomain() },
                    nextCursor: Pagination.sanitizedCursor(envelope.nextCursor))
    }

    func brief(id: String) async throws -> Brief {
        let dto: BriefDTO = try await get(Endpoint.brief(id: id))
        return dto.toDomain()
    }

    func material(briefID: String, materialID: String) async throws -> Material {
        let dto: MaterialDTO = try await get(Endpoint.material(briefID: briefID, materialID: materialID))
        guard let material = dto.toDomain() else { throw APIError.decodingFailed }
        return material
    }

    func runs(channelID: String, cursor: String? = nil, limit: Int = Pagination.defaultLimit) async throws -> Page<Run> {
        let envelope: PageEnvelope<RunDTO> = try await get(
            Endpoint.runs(channelID: channelID, cursor: cursor, limit: limit)
        )
        return Page(items: envelope.items.map { $0.toDomain() },
                    nextCursor: Pagination.sanitizedCursor(envelope.nextCursor))
    }

    func run(id: String) async throws -> Run {
        let dto: RunDTO = try await get(Endpoint.run(id: id))
        return dto.toDomain()
    }

    /// 跨频道全量日报，按创建时间倒序。首屏只需一次请求。
    func allBriefs(cursor: String? = nil, limit: Int = Pagination.defaultLimit) async throws -> Page<Brief> {
        let envelope: PageEnvelope<BriefDTO> = try await get(
            Endpoint.allBriefs(cursor: cursor, limit: limit)
        )
        return Page(items: envelope.items.map { $0.toDomain() },
                    nextCursor: Pagination.sanitizedCursor(envelope.nextCursor))
    }

    /// 直接新建频道（不再需要预设）。
    func createChannel(
        name: String,
        prompt: String,
        tone: String,
        schedule: Schedule,
        collectorSkillIDs: [String],
        enabled: Bool = true
    ) async throws -> Channel {
        let body = try JSONEncoder().encode(
            CreateChannelBody(
                name: name,
                prompt: prompt,
                tone: tone,
                schedule: schedulePayload(schedule),
                collectorSkillIds: Array(Set(collectorSkillIDs)).sorted(),
                enabled: enabled
            )
        )
        let dto: ChannelDTO = try await send(Endpoint.createChannel, method: "POST", body: body)
        return dto.toDomain()
    }

    /// Legacy source labels are rejected; callers must explicitly migrate stable Skill IDs.
    func createChannel(name: String, prompt: String, tone: String, schedule: Schedule,
                       connectorIDs: [String]) async throws -> Channel {
        throw APIError.collectorMigrationRequired
    }

    func collectorSkills(cursor: String?, limit: Int = Pagination.maxLimit) async throws -> Page<CollectorSkill> {
        let envelope: PageEnvelope<CollectorSkillDTO> = try await get(.collectorSkills(cursor: cursor, limit: limit))
        return Page(items: envelope.items.map { $0.toDomain() },
                    nextCursor: Pagination.sanitizedCursor(envelope.nextCursor))
    }

    func collectorSkills() async throws -> [CollectorSkill] {
        var cursor: String?
        var seen = Set<String>()
        var items: [CollectorSkill] = []
        repeat {
            let page = try await collectorSkills(cursor: cursor)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { break }
        } while cursor != nil
        return items
    }

    /// 服务端设置：目前只需要时区。
    func settings() async throws -> SettingsDTO {
        try await get(Endpoint.settings)
    }

    /// 软删除频道。成功返回被删除的 id。
    func deleteChannel(id: String) async throws -> String {
        let dto: DeleteChannelResponseDTO = try await send(
            .channel(id: id),
            method: "DELETE",
            body: nil
        )
        return dto.id
    }

    func connectors() async throws -> [Connector] {
        let envelope: PageEnvelope<ConnectorDTO> = try await get(Endpoint.connectors)
        return envelope.items.map { $0.toDomain() }
    }

    // MARK: 订阅

    /// 订阅一个已公开频道。重复订阅是幂等的：服务端 200 与 201 都返回同一条记录。
    @discardableResult
    func subscribe(channelID: String, color: String) async throws -> SubscriptionDTO {
        let body = try JSONEncoder().encode(SubscribeBody(color: color))
        return try await send(Endpoint.subscribe(channelID: channelID), method: "POST", body: body)
    }

    /// 只改订阅颜色；返回完整 channel DTO，便于直接刷新列表项。
    @discardableResult
    func updateSubscriptionColor(channelID: String, color: String) async throws -> Channel {
        let body = try JSONEncoder().encode(SubscriptionColorBody(color: color))
        let dto: ChannelDTO = try await send(
            Endpoint.subscribe(channelID: channelID),
            method: "PATCH",
            body: body
        )
        return dto.toDomain()
    }

    /// 取消订阅。频道与已发布日报不会删除，只是立即对本人不可见。
    func unsubscribe(channelID: String) async throws {
        let _: UnsubscribeResponseDTO = try await send(
            Endpoint.subscribe(channelID: channelID),
            method: "DELETE",
            body: nil
        )
    }

    /// 复制成自己的私有频道；服务端同时取消原订阅。
    func forkChannel(id: String, name: String? = nil) async throws -> Channel {
        let body = try JSONEncoder().encode(ForkChannelBody(name: name))
        let dto: ChannelDTO = try await send(Endpoint.fork(channelID: id), method: "POST", body: body)
        return dto.toDomain()
    }

    func cursor(since: Date?) async throws -> CursorPayload {
        let dto: CursorDTO = try await get(Endpoint.cursor(since: since))
        return dto.toDomain()
    }

    func askHistory(briefID: String, cursor: String? = nil, limit: Int = Pagination.defaultLimit) async throws -> Page<AskTurn> {
        let envelope: PageEnvelope<AskTurnDTO> = try await get(
            Endpoint.askHistory(briefID: briefID, cursor: cursor, limit: limit)
        )
        return Page(items: envelope.items.map { $0.toDomain() },
                    nextCursor: Pagination.sanitizedCursor(envelope.nextCursor))
    }

    func ask(briefID: String, message: String) async throws -> AskReply {
        let body = try JSONEncoder().encode(AskRequestBody(message: message))
        let dto: AskResponseDTO = try await send(Endpoint.ask(briefID: briefID), method: "POST", body: body)
        return AskReply(
            turn: AskTurn(
                id: UUID().uuidString,
                role: .assistant,
                message: dto.answer,
                createdAt: Date()
            ),
            citedItemIDs: dto.citedItemIds ?? [],
            isDeterministic: dto.deterministic ?? false
        )
    }

    func patchChannel(id: String, changes: ChannelChanges) async throws -> Channel {
        let body = try JSONEncoder().encode(ChannelPatchBody(changes: changes))
        let dto: ChannelDTO = try await send(Endpoint.channel(id: id), method: "PATCH", body: body)
        return dto.toDomain()
    }

    /// 把 Schedule 序列化成服务端要的 `{ day: ["HH:MM"] }`，省略空星期。
    private func schedulePayload(_ schedule: Schedule) -> [String: [String]] {
        var payload: [String: [String]] = [:]
        for weekday in Schedule.weekdays {
            let times = schedule.times(for: weekday)
            if !times.isEmpty { payload[weekday.key] = times }
        }
        return payload
    }

    // MARK: 请求构造与响应处理

    private func get<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        try await send(endpoint, method: "GET", body: nil)
    }

    private func send<T: Decodable>(_ endpoint: Endpoint, method: String, body: Data?) async throws -> T {
        let request = try makeRequest(endpoint, method: method, body: body)
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            // 传输层可能直接抛出 URLError（测试替身或自定义实现），在此统一归一化。
            throw APIError.normalize(transportError: error)
        }

        guard (200..<300).contains(response.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw envelope.normalized
            }
            if response.statusCode == 401 { throw APIError.unauthorized }
            if response.statusCode == 404 { throw APIError.notFound }
            throw APIError.server("HTTP \(response.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

    private func makeRequest(_ endpoint: Endpoint, method: String, body: Data?) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidConfiguration
        }
        components.path = endpoint.path
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else { throw APIError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuthorization {
            guard let token = credentials.token(), !token.isEmpty else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

// MARK: - 基础地址

enum BaseURLDefaults {
    /// 服务地址固定：客户端不再提供修改入口，用户无需也不能改。
    /// 保留 `host` 常量而不是散落字面量，方便将来换环境时只改一处。
    static let host = "https://reachapi.niuma.art"

    static var url: URL {
        URL(string: host) ?? URL(fileURLWithPath: "/")
    }

    /// 接受用户输入的地址：补齐 scheme，去掉尾部斜杠；不接受空值与非 http(s)。
    static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host() != nil else {
            return nil
        }
        return url
    }
}
