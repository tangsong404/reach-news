import Foundation
import Observation

// MARK: - 会话（鉴权与连接）
//
// 双验证：/health 确认服务可达，/api/v1/channels 确认 token 有效。
// 两者都通过才写入 Keychain 并覆盖旧凭证。

@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(APIError)
    }

    private(set) var state: State = .signedOut
    private(set) var session: AuthSession?
    private(set) var serviceTime: Date?

    var baseURLString: String
    var username: String = ""
    /// 密码不常驻内存：登录成功后立即清空。
    var password: String = ""

    @ObservationIgnored private let credentials: CredentialProviding
    @ObservationIgnored private let preferences: PreferencesStoring
    @ObservationIgnored private let makeClient: (URL) -> APIClient
    /// 限流后到此时刻前禁止再提交，避免每一次重试都延长锁定。
    @ObservationIgnored private var blockedUntil: Date?

    init(
        credentials: CredentialProviding,
        preferences: PreferencesStoring,
        makeClient: @escaping (URL) -> APIClient
    ) {
        self.credentials = credentials
        self.preferences = preferences
        self.makeClient = makeClient
        self.baseURLString = preferences.baseURLString
        if let token = credentials.token(), !token.isEmpty,
           let expires = credentials.expiresAt(), expires > Date() {
            session = AuthSession(token: token, expiresAt: expires, userName: "")
            state = .signedIn
        } else if credentials.token()?.isEmpty == false {
            // 有 token 但已过期：清掉，回登录页。
            credentials.clearToken()
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var isSigningIn: Bool {
        if case .signingIn = state { return true }
        return false
    }

    var resolvedBaseURL: URL {
        BaseURLDefaults.parse(baseURLString) ?? BaseURLDefaults.url
    }

    var credentialSummaryKey: String {
        session == nil ? "connection.credential.missing" : "connection.credential.stored"
    }

    var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isSigningIn
            && !isThrottled
    }

    /// 限流冷却中；此时连正确密码也会被拒，因此直接禁用提交。
    var isThrottled: Bool {
        guard let blockedUntil else { return false }
        return blockedUntil > Date()
    }

    var throttleRemainingSeconds: Int {
        guard let blockedUntil else { return 0 }
        return max(0, Int(blockedUntil.timeIntervalSinceNow.rounded(.up)))
    }

    /// 账号密码登录，成功后才写入会话凭证。
    func signIn() async -> Bool {
        guard let url = BaseURLDefaults.parse(baseURLString) else {
            state = .failed(.invalidConfiguration)
            return false
        }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            state = .failed(.unauthorized)
            return false
        }
        if isThrottled { return false }

        state = .signingIn
        let client = makeClient(url)

        do {
            let newSession = try await client.login(username: name, password: password)

            // 凭证只有在登录成功后才会落到 Keychain。
            try credentials.store(token: newSession.token)
            credentials.store(expiresAt: newSession.expiresAt)

            preferences.baseURLString = url.absoluteString
            baseURLString = url.absoluteString
            session = AuthSession(
                token: newSession.token,
                expiresAt: newSession.expiresAt,
                userName: newSession.userName.isEmpty ? name : newSession.userName
            )
            password = ""
            blockedUntil = nil
            state = .signedIn
            return true
        } catch let error as APIError {
            if error.isTooManyAttempts {
                // 服务端 5 分钟窗口；本地同样冷却，绝不自动重试。
                blockedUntil = Date().addingTimeInterval(5 * 60)
            }
            // 登录失败不写入任何凭证，也不覆盖既有会话。
            state = .failed(error)
            return false
        } catch {
            state = .failed(.transport(error.localizedDescription))
            return false
        }
    }

    /// 启动时校验已保存的会话是否仍可用。
    func validateStoredSession() async {
        guard let session else {
            state = .signedOut
            return
        }
        if session.isExpired() {
            clearSession()
            state = .signedOut
            return
        }
        let client = makeClient(resolvedBaseURL)
        do {
            _ = try await client.channels(limit: 1)
            state = .signedIn
        } catch let error as APIError {
            if error == .unauthorized {
                // 管理员重置密码会清空所有会话；直接回登录页。
                clearSession()
                state = .signedOut
            } else {
                state = .signedIn
            }
        } catch {
            state = .signedIn
        }
    }

    /// 注销：先通知服务端，无论结果如何都清本地凭证。
    func signOut() async {
        let client = makeClient(resolvedBaseURL)
        _ = try? await client.logout()
        clearSession()
        username = ""
        password = ""
        state = .signedOut
    }

    /// 任何请求收到 401 都调用这里：清会话并回登录页，不自动重试。
    func handleUnauthorized() {
        clearSession()
        state = .signedOut
    }

    /// 凭证到期时间。
    var expiresAt: Date? {
        session?.expiresAt
    }

    private func clearSession() {
        credentials.clearToken()
        session = nil
    }

    func resetError() {
        if case .failed = state {
            state = session == nil ? .signedOut : .signedIn
        }
    }
}

// MARK: - 错误文案
//
// 把归一化错误转成可展示的本地化键，避免视图里散落 switch。

extension APIError {
    var messageKey: String {
        switch self {
        case .offline: return "error.offline"
        case .transport: return "error.transport"
        case .unauthorized: return "error.unauthorized"
        case .tooManyAttempts: return "error.tooManyAttempts"
        case .invalidConnector: return "error.invalidConnector"
        case .notFound: return "error.notFound"
        case .invalidInput: return "error.invalidInput"
        case .busy: return "error.busy"
        case .badRequest: return "error.badRequest"
        case .server: return "error.server"
        case .decodingFailed: return "error.decoding"
        case .invalidConfiguration: return "error.configuration"
        }
    }

    /// 服务端给出的原始说明，用于在通用文案下补充细节。
    var detailText: String? {
        switch self {
        case .invalidConnector(let message), .invalidInput(let message), .busy(let message),
             .badRequest(let message), .server(let message):
            return message.isEmpty ? nil : message
        case .transport(let message):
            return message.isEmpty ? nil : message
        case .offline, .unauthorized, .tooManyAttempts, .notFound, .decodingFailed, .invalidConfiguration:
            return nil
        }
    }
}
