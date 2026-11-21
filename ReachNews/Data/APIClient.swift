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
    case channels(cursor: String?, limit: Int)
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
    case presets
    case instantiatePreset(id: String)
    case settings

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
        case .presets:
            return "/api/v1/presets"
        case .instantiatePreset(let id):
            return "/api/v1/presets/\(id)/instantiate"
        case .settings:
            return "/api/v1/settings"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .channels(let cursor, let limit),
             .askHistory(_, let cursor, let limit):
            return Pagination.queryItems(cursor: cursor, limit: limit)
        case .briefs(_, let cursor, let limit),
             .runs(_, let cursor, let limit),
             .allBriefs(let cursor, let limit):
            return Pagination.queryItems(cursor: cursor, limit: limit)
        case .cursor(let since):
            return [URLQueryItem(name: "since", value: PollingBaseline.sinceString(since))]
        case .health, .login, .logout, .createChannel, .channel, .brief, .material, .run, .ask,
             .connectors, .presets, .instantiatePreset, .settings:
            return []
        }
    }

    var requiresAuthorization: Bool {
        switch self {
        case .health, .login: return false
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

    /// 注销当前会话凭证；失败不阻碍本地清理。
    func logout() async throws {
        let _: LogoutResponseDTO = try await send(Endpoint.logout, method: "POST", body: nil)
    }

    func channels(cursor: String? = nil, limit: Int = Pagination.defaultLimit) async throws -> Page<Channel> {
        let envelope: PageEnvelope<ChannelDTO> = try await get(Endpoint.channels(cursor: cursor, limit: limit))
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
        connectorIDs: [String]
    ) async throws -> Channel {
        let body = try JSONEncoder().encode(
            CreateChannelBody(
                name: name,
                prompt: prompt,
                tone: tone,
                schedule: schedulePayload(schedule),
                connectorIds: connectorIDs
            )
        )
        let dto: ChannelDTO = try await send(Endpoint.createChannel, method: "POST", body: body)
        return dto.toDomain()
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

    func presets() async throws -> [ChannelPreset] {
        let envelope: PageEnvelope<PresetDTO> = try await get(Endpoint.presets)
        return envelope.items.map { $0.toDomain() }
    }

    func instantiatePreset(id: String) async throws -> Channel {
        let dto: ChannelDTO = try await send(Endpoint.instantiatePreset(id: id), method: "POST", body: nil)
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
