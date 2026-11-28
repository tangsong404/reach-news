import XCTest
@testable import ReachNews

// MARK: - 注册
//
// 邀请码注册（POST /api/v1/register）。覆盖：
// 请求体编码、成功即建会话（不再调登录）、失败按 code 保留可展示信息。
//
// 不用 raw string：本机 tree-sitter 解析器不支持 #"..."#，会误报语法错误。

final class RegistrationTests: XCTestCase {

    @MainActor
    private func makeSession(
        transport: StubTransport,
        credentials: InMemoryCredentials = InMemoryCredentials(),
        preferences: InMemoryPreferences = InMemoryPreferences()
    ) -> SessionStore {
        let client = TestClient.make(transport: transport, token: nil)
        return SessionStore(
            credentials: credentials,
            preferences: preferences,
            makeClient: { _ in client }
        )
    }

    // MARK: 请求编码

    func testRegisterRequestEncodesAllFields() throws {
        let request = RegisterRequest(
            nickname: "前端",
            email: "fe@example.com",
            password: "password-123",
            passwordConfirm: "password-123",
            inviteCode: "KYYPVTJB27NUCQE2",
            captchaToken: "captcha-token",
            emailCode: "123456"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // 字段名必须与服务端一致，否则会得到 invalid_input。
        XCTAssertEqual(json["nickname"] as? String, "前端")
        XCTAssertEqual(json["email"] as? String, "fe@example.com")
        XCTAssertEqual(json["password"] as? String, "password-123")
        XCTAssertEqual(json["passwordConfirm"] as? String, "password-123")
        XCTAssertEqual(json["inviteCode"] as? String, "KYYPVTJB27NUCQE2")
        XCTAssertEqual(json["captchaToken"] as? String, "captcha-token")
        XCTAssertEqual(json["emailCode"] as? String, "123456")
    }

    // MARK: 成功

    @MainActor
    func testRegisterSuccessEstablishesSessionWithoutSecondLogin() async {
        // 实测响应形状：token + user（含 email/tier/avatarUrl）+ capabilities。
        let json = """
        {"token":"session-abc","expiresAt":"2099-01-01T00:00:00.000Z",\
        "user":{"id":"usr_1","name":"前端","email":"fe@example.com","tier":"ultra","avatarUrl":null},\
        "capabilities":{"tier":"ultra","ask":true,"briefImages":true,"channelLimit":10}}
        """
        let transport = StubTransport(json: json)
        let credentials = InMemoryCredentials()
        let session = makeSession(transport: transport, credentials: credentials)

        let failure = await session.register(
            nickname: "前端",
            email: "fe@example.com",
            password: "password-123",
            passwordConfirm: "password-123",
            inviteCode: "KYYPVTJB27NUCQE2"
        )

        XCTAssertNil(failure)
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(credentials.storedToken, "session-abc")
        XCTAssertEqual(session.profile?.name, "前端")
        XCTAssertEqual(session.profile?.tier, "ultra")
        XCTAssertEqual(session.capabilities.channelLimit, 10)

        // 只调了一次：注册接口自己返回 token，不该再调登录。
        XCTAssertEqual(transport.recorded.count, 1)
        XCTAssertEqual(transport.recorded.first?.url.path, "/api/v1/register")
        XCTAssertEqual(transport.recorded.first?.method, "POST")
        // 注册是公开端点，不带 Bearer。
        XCTAssertNil(transport.recorded.first?.authorization)
    }

    @MainActor
    func testRegisterSendsCaptchaAndEmailCodeWhenProvided() async throws {
        let json = """
        {"token":"t","expiresAt":"2099-01-01T00:00:00.000Z",\
        "user":{"id":"usr_1","name":"n","email":"e@x.com","tier":"free","avatarUrl":null},\
        "capabilities":{"tier":"free","ask":true,"briefImages":false,"channelLimit":1}}
        """
        let transport = StubTransport(json: json)
        let session = makeSession(transport: transport)

        _ = await session.register(
            nickname: "n", email: "e@x.com",
            password: "password-123", passwordConfirm: "password-123",
            inviteCode: "CODE", captchaToken: "cap-token", emailCode: "654321"
        )

        let body = try XCTUnwrap(transport.recorded.first?.body)
        let json2 = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json2["captchaToken"] as? String, "cap-token")
        XCTAssertEqual(json2["emailCode"] as? String, "654321")
    }

    // MARK: 邀请码可选

    @MainActor
    func testRegisterWithoutInviteCodeOmitsTheField() async throws {
        // 开放注册模式下不带码；不应发送空字符串，服务端会当成无效码。
        let json = """
        {"token":"t","expiresAt":"2099-01-01T00:00:00.000Z",\
        "user":{"id":"usr_1","name":"n","email":"e@x.com","tier":"free","avatarUrl":null},\
        "capabilities":{"tier":"free","ask":true,"briefImages":false,"channelLimit":1}}
        """
        let transport = StubTransport(json: json)
        let session = makeSession(transport: transport)

        _ = await session.register(
            nickname: "n", email: "e@x.com",
            password: "password-123", passwordConfirm: "password-123",
            inviteCode: ""
        )

        let body = try XCTUnwrap(transport.recorded.first?.body)
        let json2 = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json2["inviteCode"], "空邀请码不应作为字段发送")
        XCTAssertTrue(session.isSignedIn)
    }

    @MainActor
    func testInviteRequiredIsReportedWhenServerRejectsMissingCode() async throws {
        // 「需要邀请码」模式下不带码：服务端返回 invite_not_found，需保留给界面。
        let json = "{\"error\":{\"code\":\"invite_not_found\",\"message\":\"邀请码无效，请检查\"}}"
        let transport = StubTransport(json: json, status: 400)
        let session = makeSession(transport: transport)

        let failure = await session.register(
            nickname: "n", email: "e@x.com",
            password: "password-123", passwordConfirm: "password-123",
            inviteCode: ""
        )

        let error = try XCTUnwrap(failure)
        XCTAssertEqual(error.code, "invite_not_found")
        XCTAssertFalse(session.isSignedIn)
    }

    // MARK: 验证码冷却

    func testRetryAfterSecondsIsParsedFrom429() throws {
        let payload = """
        {"error":{"code":"code_too_frequent","message":"请等待 42 秒后再获取验证码"}, "retryAfterSeconds":42}
        """
        let failure = EmailCodeFailure(from: Data(payload.utf8), statusCode: 429)

        XCTAssertEqual(failure.code, "code_too_frequent")
        XCTAssertEqual(failure.retryAfterSeconds, 42)
        XCTAssertEqual(failure.message, "请等待 42 秒后再获取验证码")
    }

    func testMailNotConfiguredIsRecognised() throws {
        let payload = """
        {"error":{"code":"mail_not_configured","message":"邮件服务尚未配置"}}
        """
        let failure = EmailCodeFailure(from: Data(payload.utf8), statusCode: 503)

        XCTAssertTrue(failure.isMailNotConfigured)
        XCTAssertEqual(failure.retryAfterSeconds, nil)
    }

    func testCaptchaCodesAreRecognised() throws {
        for code in ["captcha_required", "captcha_failed"] {
            let payload = "{\"error\":{\"code\":\"\(code)\",\"message\":\"x\"}}"
            let failure = EmailCodeFailure(from: Data(payload.utf8), statusCode: 400)
            XCTAssertTrue(failure.isCaptchaRequired, code)
        }
    }

    // MARK: 失败

    @MainActor
    func testRegisterRejectedKeepsServerCodeAndMessage() async throws {
        let json = "{\"error\":{\"code\":\"invite_used\",\"message\":\"该邀请码已被使用\"}}"
        let transport = StubTransport(json: json, status: 400)
        let credentials = InMemoryCredentials()
        let session = makeSession(transport: transport, credentials: credentials)

        let failure = await session.register(
            nickname: "前端",
            email: "fe@example.com",
            password: "password-123",
            passwordConfirm: "password-123",
            inviteCode: "USED"
        )

        let error = try XCTUnwrap(failure)
        XCTAssertEqual(error.code, "invite_used")
        // 服务端已给中文 message：客户端优先展示它，不做二次翻译。
        XCTAssertEqual(error.message, "该邀请码已被使用")
        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(credentials.storedToken)
    }

    func testAllKnownRejectionCodesMapToFallbackKeys() {
        // 服务端可能只给 code 不给 message，此时界面用本地兜底文案。
        let codes = [
            "invite_not_found", "invite_used", "invite_revoked",
            "nickname_required", "nickname_too_long", "nickname_taken",
            "email_required", "email_invalid", "email_taken",
            "password_required", "password_too_short",
            "password_confirm_required", "password_mismatch"
        ]

        for code in codes {
            let error = RegistrationError(code: code, message: "")
            XCTAssertEqual(error.fallbackKey, "register.error." + code)
        }
    }

    // MARK: 登录标识

    @MainActor
    func testLoginAcceptsEmailAsUsername() async throws {
        // 服务端 username 字段同时接受邮箱与昵称；客户端原样提交即可。
        let json = """
        {"token":"session-abc","expiresAt":"2099-01-01T00:00:00.000Z",\
        "user":{"id":"usr_1","name":"前端","email":"fe@example.com","tier":"free","avatarUrl":null}}
        """
        let transport = StubTransport(json: json)
        let session = makeSession(transport: transport)
        session.username = "fe@example.com"
        session.password = "password-123"

        let ok = await session.signIn()

        XCTAssertTrue(ok)
        let body = try XCTUnwrap(transport.recorded.first?.body)
        let json2 = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json2["username"] as? String, "fe@example.com")
    }
}
