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

    /// 当前用户资料。冷启动恢复会话后由 `refreshProfile()` 填充。
    /// 退出登录时必须清空，否则换账号会看到上一个账号的头部信息。
    private(set) var profile: UserProfile?
    /// 档位能力：界面据此决定是否显示追问入口、频道上限提示等。
    private(set) var capabilities: UserCapabilities = .unknown
    /// 资料是否正在拉取；界面据此显示占位而不是空行。
    private(set) var isRefreshingProfile = false
    /// 注册进行中；界面据此禁用提交。
    private(set) var isRegistering = false

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
            let resolvedName = newSession.userName.isEmpty ? name : newSession.userName
            // 只记展示名，不碰凭证；冷启动恢复会话时头部靠它显示用户名。
            preferences.lastUserName = resolvedName
            session = AuthSession(
                token: newSession.token,
                expiresAt: newSession.expiresAt,
                userName: resolvedName
            )
            password = ""
            blockedUntil = nil
            state = .signedIn
            // 登录响应已带 user 与 capabilities，但字段可能不全（例如缺 email）。
            // 这里异步补一次 /me；失败不回滚登录——资料缺失不该把人踢回登录页。
            Task { await self.refreshProfile() }
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
            // 冷启动必须拉一次 /me：Keychain 里的会话没有用户名，
            // 只靠本地缓存会让「我的」页头部空着。
            await refreshProfile()
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

    /// 注销：先通知服务端，无论结果如何都清本地凭证与用户资料。
    func signOut() async {
        let client = makeClient(resolvedBaseURL)
        _ = try? await client.logout()
        clearSession()
        // 展示名也要清：否则 userName 会从偏好项回退成上一个账号的名字。
        preferences.lastUserName = ""
        username = ""
        password = ""
        state = .signedOut
    }

    /// 仅供测试注入资料：生产路径只通过 `refreshProfile()` 与注册写入。
    func applyProfileForTesting(_ profile: UserProfile, capabilities: UserCapabilities? = nil) {
        self.profile = profile
        if let capabilities { self.capabilities = capabilities }
        if !profile.name.isEmpty { preferences.lastUserName = profile.name }
    }

    /// 拉取当前用户资料与能力。
    ///
    /// 失败不改变登录状态：离线时头部显示占位，比把用户踢回登录页更合理。
    /// 401 例外——凭证真的失效时仍按既有规则退回登录页。
    func refreshProfile() async {
        guard session != nil else { return }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        let client = makeClient(resolvedBaseURL)
        do {
            let (profile, capabilities) = try await client.me()
            self.profile = profile
            self.capabilities = capabilities
            if !profile.name.isEmpty {
                // 顺手补上展示名，下次冷启动即使 /me 暂时失败也不会空行。
                preferences.lastUserName = profile.name
            }
        } catch let error as APIError where error == .unauthorized {
            handleUnauthorized()
        } catch {
            // 网络或服务端异常：保留既有状态，界面用占位兜底。
        }
    }

    /// 用邀请码注册并直接建立会话（注册响应已带 token，无需再登录）。
    /// 返回 nil 表示成功，否则返回需要展示的注册错误。
    func register(
        nickname: String,
        email: String,
        password: String,
        passwordConfirm: String,
        inviteCode: String,
        captchaToken: String? = nil,
        emailCode: String? = nil
    ) async -> RegistrationError? {
        guard let url = BaseURLDefaults.parse(baseURLString) else {
            return RegistrationError(code: "invalid_configuration", message: "")
        }
        if isRegistering { return RegistrationError(code: "busy", message: "") }
        isRegistering = true
        defer { isRegistering = false }

        let client = makeClient(url)
        do {
            let outcome = try await client.register(
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                passwordConfirm: passwordConfirm,
                // 开放注册模式下不带码；空串按 nil 发送，不塞一个空字符串。
                inviteCode: {
                    let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }(),
                captchaToken: captchaToken,
                emailCode: emailCode
            )
            switch outcome {
            case let .rejected(error):
                return error
            case let .success(newSession, profile, capabilities):
                try credentials.store(token: newSession.token)
                credentials.store(expiresAt: newSession.expiresAt)
                preferences.baseURLString = url.absoluteString
                baseURLString = url.absoluteString
                preferences.lastUserName = profile.name
                session = AuthSession(
                    token: newSession.token,
                    expiresAt: newSession.expiresAt,
                    userName: profile.name
                )
                self.profile = profile
                self.capabilities = capabilities
                state = .signedIn
                return nil
            }
        } catch let error as APIError {
            return RegistrationError(code: error.errorCode?.rawValue ?? "unknown", message: "")
        } catch {
            return RegistrationError(code: "offline", message: "")
        }
    }

    /// 上传头像并刷新资料。
    @discardableResult
    func uploadAvatar(imageData: Data) async -> Bool {
        guard session != nil else { return false }
        let client = makeClient(resolvedBaseURL)
        do {
            _ = try await client.uploadAvatar(imageData: imageData)
            await refreshProfile()
            return true
        } catch {
            return false
        }
    }

    /// 人机验证配置；注册页进入时取一次。
    func loadCaptchaConfig() async -> CaptchaConfigDTO? {
        try? await makeClient(resolvedBaseURL).captchaConfig()
    }

    /// 请求邮箱验证码。返回失败信息供界面逐项展示（含 429 冷却秒数）。
    func requestEmailCode(
        email: String,
        purpose: String = "register",
        captchaToken: String? = nil
    ) async -> EmailCodeFailure? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EmailCodeFailure.emptyEmail
        }
        do {
            let outcome = try await makeClient(resolvedBaseURL).requestEmailCode(
                email: trimmed,
                purpose: purpose,
                captchaToken: captchaToken
            )
            switch outcome {
            case .sent: return nil
            case let .rejected(failure): return failure
            }
        } catch {
            return nil
        }
    }

    /// 改昵称；成功后就地刷新资料，不重打 GET。
    func updateNickname(_ name: String) async -> RegistrationError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return RegistrationError(code: "nickname_required", message: "")
        }
        let client = makeClient(resolvedBaseURL)
        do {
            let (profile, capabilities) = try await client.updateNickname(trimmed)
            self.profile = profile
            self.capabilities = capabilities
            if let current = session {
                session = AuthSession(token: current.token, expiresAt: current.expiresAt, userName: profile.name)
            }
            preferences.lastUserName = profile.name
            return nil
        } catch let error as APIError {
            return RegistrationError(code: error.errorCode?.rawValue ?? "unknown", message: error.detailText ?? "")
        } catch {
            return RegistrationError(code: "offline", message: "")
        }
    }

    /// 改密码。
    ///
    /// 服务端采用方案 A：其他设备会话失效、**当前 token 保留**。
    /// 因此成功后不清理本地凭证、不踢回登录页。
    func changePassword(
        current: String,
        new: String,
        confirm: String,
        emailCode: String
    ) async -> RegistrationError? {
        guard !new.isEmpty else { return RegistrationError(code: "password_required", message: "") }
        guard new.count >= 8 else { return RegistrationError(code: "password_too_short", message: "") }
        guard !confirm.isEmpty else { return RegistrationError(code: "password_confirm_required", message: "") }
        guard new == confirm else { return RegistrationError(code: "password_mismatch", message: "") }
        guard !emailCode.trimmingCharacters(in: .whitespaces).isEmpty else {
            return RegistrationError(code: "email_code_required", message: "")
        }

        let client = makeClient(resolvedBaseURL)
        do {
            try await client.changePassword(
                current: current,
                new: new,
                confirm: confirm,
                emailCode: emailCode.trimmingCharacters(in: .whitespaces)
            )
            return nil
        } catch let error as APIError {
            return RegistrationError(code: error.errorCode?.rawValue ?? "unknown", message: error.detailText ?? "")
        } catch {
            return RegistrationError(code: "offline", message: "")
        }
    }

    /// 删除头像（幂等）。
    @discardableResult
    func deleteAvatar() async -> Bool {
        guard session != nil else { return false }
        do {
            _ = try await makeClient(resolvedBaseURL).deleteAvatar()
            await refreshProfile()
            return true
        } catch {
            return false
        }
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
        // 资料与能力跟着会话走：留着会让下一个账号看到上一个账号的头部。
        profile = nil
        capabilities = .unknown
        isRefreshingProfile = false
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
        case .removed: return "error.presetsRemoved"
        case .notPublished: return "error.notPublished"
        case .ownChannel: return "error.ownChannel"
        case .subscriberReadOnly: return "error.subscriberReadOnly"
        case .channelQuotaExceeded: return "error.channelQuotaExceeded"
        case .collectorConfiguration(let code, _):
            switch code {
            case .collectorMigrationRequired: return "error.collectorMigrationRequired"
            case .collectorSkillRequired: return "error.collectorSkillRequired"
            default: return "error.invalidCollectorSkill"
            }
        }
    }

    /// 服务端给出的原始说明，用于在通用文案下补充细节。
    var detailText: String? {
        switch self {
        case .invalidConnector(let message), .invalidInput(let message), .busy(let message),
             .badRequest(let message), .server(let message), .removed(let message),
             .notPublished(let message), .ownChannel(let message), .subscriberReadOnly(let message),
             .channelQuotaExceeded(let message), .collectorConfiguration(_, let message):
            return message.isEmpty ? nil : message
        case .transport(let message):
            return message.isEmpty ? nil : message
        case .offline, .unauthorized, .tooManyAttempts, .notFound, .decodingFailed, .invalidConfiguration:
            return nil
        }
    }
}
