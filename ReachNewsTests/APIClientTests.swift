import XCTest
@testable import ReachNews

// MARK: - 网络层行为

final class APIClientTests: XCTestCase {
    func testAuthorizationHeaderIsAttached() async throws {
        // 频道端点返回分页信封，不是 health 形状。
        let transport = StubTransport(json: #"{"items":[],"nextCursor":null}"#)
        let client = TestClient.make(transport: transport, token: "secret-token")

        _ = try await client.channels(limit: 1)

        XCTAssertEqual(transport.recorded.first?.authorization, "Bearer secret-token")
    }

    func testHealthEndpointSkipsAuthorization() async throws {
        let transport = StubTransport(json: #"{"ok":true,"service":"reach-news","time":"2026-11-20T02:01:50.774Z"}"#)
        let client = TestClient.make(transport: transport)

        let health = try await client.health()

        XCTAssertTrue(health.ok)
        XCTAssertNil(transport.recorded.first?.authorization)
        XCTAssertEqual(transport.recorded.first?.url.path, "/health")
    }

    func testMissingTokenFailsWithoutRequest() async {
        let transport = StubTransport(json: "{}")
        let client = TestClient.make(transport: transport, token: nil)

        do {
            _ = try await client.channels()
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // 没有凭证时不发请求。
        XCTAssertTrue(transport.recorded.isEmpty)
    }

    func testErrorEnvelopeIsNormalized() async {
        let transport = StubTransport(
            json: #"{"error":{"code":"invalid_input","message":"limit must be a positive integer"}}"#,
            status: 400
        )
        let client = TestClient.make(transport: transport)

        do {
            _ = try await client.channels(limit: 20)
            XCTFail("Expected failure")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalidInput("limit must be a positive integer"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnauthorizedStatusWithoutEnvelope() async {
        let transport = StubTransport(json: "", status: 401)
        let client = TestClient.make(transport: transport)

        do {
            _ = try await client.channels()
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNotFoundStatusWithoutEnvelope() async {
        let transport = StubTransport(json: "", status: 404)
        let client = TestClient.make(transport: transport)

        do {
            _ = try await client.brief(id: "brf_missing")
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportFailureBecomesOffline() async {
        let transport = StubTransport { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = TestClient.make(transport: transport)

        do {
            _ = try await client.channels()
            XCTFail("Expected offline")
        } catch let error as APIError {
            XCTAssertTrue(error.isOffline)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUndecodableBodyIsReported() async {
        let transport = StubTransport(json: "not json")
        let client = TestClient.make(transport: transport)

        do {
            _ = try await client.channels()
            XCTFail("Expected decoding failure")
        } catch let error as APIError {
            XCTAssertEqual(error, .decodingFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAskPostsMessageAndReturnsCitedItems() async throws {
        let transport = StubTransport(
            json: #"{"message":"这条哪来的","answer":"已基于归档摘要记录问题","citedItemIds":["itm_1","itm_2"],"deterministic":true}"#,
            status: 201
        )
        let client = TestClient.make(transport: transport)

        let reply = try await client.ask(briefID: "brf_1", message: "这条哪来的")

        XCTAssertEqual(reply.turn.role, .assistant)
        XCTAssertEqual(reply.turn.message, "已基于归档摘要记录问题")
        XCTAssertEqual(reply.citedItemIDs, ["itm_1", "itm_2"])
        XCTAssertTrue(reply.isDeterministic)

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/v1/briefs/brf_1/ask")
        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["message"], "这条哪来的")
    }

    func testPaginationParamsAreSentAsContractRequires() async throws {
        let transport = StubTransport(json: #"{"items":[],"nextCursor":null}"#)
        let client = TestClient.make(transport: transport)

        _ = try await client.channels(cursor: "20", limit: 40)

        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(transport.recorded.first?.url), resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "40")
        XCTAssertEqual(items.first { $0.name == "cursor" }?.value, "20")
    }

    func testNegativeCursorFromServerIsDiscarded() async throws {
        // 服务端在负 cursor 下可能返回非空 nextCursor，客户端不缓存这种值。
        let transport = StubTransport(json: #"{"items":[],"nextCursor":"-5"}"#)
        let client = TestClient.make(transport: transport)

        let page = try await client.channels(cursor: nil, limit: 20)

        XCTAssertNil(page.nextCursor)
    }

    func testLoginEndpointSendsCredentialsAndParsesSession() async throws {
        let transport = StubTransport(
            json: #"{"token":"tok-123","expiresAt":"2026-11-27T11:43:51.860Z","user":{"id":"usr_1","name":"admin"}}"#
        )
        let client = TestClient.make(transport: transport, token: nil)

        let session = try await client.login(username: "admin", password: "pw")

        XCTAssertEqual(session.token, "tok-123")
        XCTAssertEqual(session.userName, "admin")
        // Evaluate relative to a fixed instant before fixture expiry, not wall-clock time.
        XCTAssertFalse(session.isExpired(now: Date(timeIntervalSince1970: 1_700_000_000)))

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/v1/login")
        // 登录本身不需要 Authorization。
        XCTAssertNil(request.authorization)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(json["username"], "admin")
        XCTAssertEqual(json["password"], "pw")
    }

    func testTooManyAttemptsIsItsOwnError() async {
        let transport = StubTransport(
            json: #"{"error":{"code":"too_many_attempts","message":"Too many failed login attempts"}}"#,
            status: 429
        )
        let client = TestClient.make(transport: transport, token: nil)

        do {
            _ = try await client.login(username: "admin", password: "pw")
            XCTFail("Expected tooManyAttempts")
        } catch let error as APIError {
            XCTAssertTrue(error.isTooManyAttempts)
            XCTAssertEqual(error.messageKey, "error.tooManyAttempts")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLogoutRequiresAuthorization() async throws {
        let transport = StubTransport(json: #"{"ok":true}"#)
        let client = TestClient.make(transport: transport, token: "session-token")

        try await client.logout()

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.url.path, "/api/v1/logout")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.authorization, "Bearer session-token")
    }

    func testWithBaseURLProducesIndependentClient() async throws {
        let transport = StubTransport(json: #"{"ok":true,"service":"reach-news","time":null}"#)
        let client = TestClient.make(transport: transport)
        let alternate = client.withBaseURL(URL(string: "http://localhost:5100")!)

        _ = try await alternate.health()

        XCTAssertEqual(transport.recorded.first?.url.host(), "localhost")
        XCTAssertEqual(client.baseURL.host(), BaseURLDefaults.url.host())
    }
}

// MARK: - 会话登录

final class SessionStoreTests: XCTestCase {
    @MainActor
    private func makeSession(
        credentials: InMemoryCredentials = InMemoryCredentials(),
        transport: StubTransport
    ) -> SessionStore {
        let client = TestClient.make(transport: transport, token: nil)
        return SessionStore(
            credentials: credentials,
            preferences: InMemoryPreferences(),
            makeClient: { _ in client }
        )
    }

    @MainActor
    func testSignInStoresSessionFromLoginResponse() async {
        let credentials = InMemoryCredentials()
        let transport = StubTransport(json: #"{"token":"session-abc","expiresAt":"2099-01-01T00:00:00.000Z","user":{"id":"usr_1","name":"admin"}}"#)
        let session = makeSession(credentials: credentials, transport: transport)
        session.username = "admin"
        session.password = "secret"

        let ok = await session.signIn()

        XCTAssertTrue(ok)
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(credentials.storedToken, "session-abc")
        XCTAssertNotNil(credentials.storedExpiry)
        // 密码不驻留。
        XCTAssertEqual(session.password, "")
        // 登录本身只打 /login；/me 是登录后的补充拉取，异步进行。
        let loginRequests = transport.recorded.filter { $0.url.path == "/api/v1/login" }
        XCTAssertEqual(loginRequests.count, 1)
        XCTAssertEqual(loginRequests.first?.method, "POST")
    }

    @MainActor
    func testSignInFailureDoesNotStoreCredential() async {
        let credentials = InMemoryCredentials()
        let transport = StubTransport(
            json: #"{"error":{"code":"unauthorized","message":"Invalid username or password"}}"#,
            status: 401
        )
        let session = makeSession(credentials: credentials, transport: transport)
        session.username = "admin"
        session.password = "wrong"

        let ok = await session.signIn()

        XCTAssertFalse(ok)
        XCTAssertNil(credentials.storedToken)
        XCTAssertFalse(session.isSignedIn)
    }

    @MainActor
    func testThrottledLoginBlocksFurtherAttempts() async {
        let credentials = InMemoryCredentials()
        let transport = StubTransport(
            json: #"{"error":{"code":"too_many_attempts","message":"Too many failed login attempts; try again later"}}"#,
            status: 429
        )
        let session = makeSession(credentials: credentials, transport: transport)
        session.username = "admin"
        session.password = "secret"

        _ = await session.signIn()
        XCTAssertTrue(session.isThrottled)
        XCTAssertFalse(session.canSubmit)
        XCTAssertGreaterThan(session.throttleRemainingSeconds, 0)

        // 冷却期内不得再发请求（否则会把锁定续期）。
        let recorded = transport.recorded.count
        let second = await session.signIn()
        XCTAssertFalse(second)
        XCTAssertEqual(transport.recorded.count, recorded)
    }

    @MainActor
    func testExpiredStoredSessionIsDiscardedOnInit() {
        let credentials = InMemoryCredentials(
            token: "old-session",
            expiresAt: Date(timeIntervalSinceNow: -60)
        )
        let session = makeSession(credentials: credentials, transport: StubTransport(json: "{}"))

        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(credentials.storedToken)
    }

    @MainActor
    func testValidStoredSessionRestoresSignedIn() {
        let credentials = InMemoryCredentials(
            token: "live-session",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let session = makeSession(credentials: credentials, transport: StubTransport(json: "{}"))

        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(credentials.storedToken, "live-session")
    }

    @MainActor
    func testUnauthorizedClearsSession() async {
        let credentials = InMemoryCredentials(
            token: "live-session",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let session = makeSession(credentials: credentials, transport: StubTransport(json: "{}"))
        XCTAssertTrue(session.isSignedIn)

        session.handleUnauthorized()

        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(credentials.storedToken)
    }

    @MainActor
    func testSignOutClearsSessionEvenIfLogoutFails() async {
        let credentials = InMemoryCredentials(
            token: "live-session",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let transport = StubTransport(json: #"{"error":{"code":"unauthorized","message":"no"}}"#, status: 401)
        let session = makeSession(credentials: credentials, transport: transport)

        await session.signOut()

        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(credentials.storedToken)
    }

    @MainActor
    func testInvalidBaseURLIsRejectedBeforeRequest() async {
        let transport = StubTransport(json: "{}")
        let session = makeSession(transport: transport)
        session.baseURLString = "ftp://nope"
        session.username = "admin"
        session.password = "secret"

        let ok = await session.signIn()

        XCTAssertFalse(ok)
        XCTAssertTrue(transport.recorded.isEmpty)
    }

    @MainActor
    func testEmptyUsernameIsRejected() async {
        let transport = StubTransport(json: "{}")
        let session = makeSession(transport: transport)
        session.username = "   "
        session.password = "secret"

        let ok = await session.signIn()

        XCTAssertFalse(ok)
        XCTAssertTrue(transport.recorded.isEmpty)
    }
}

// MARK: - 新端点（2026-11-21）

final class NewEndpointTests: XCTestCase {
    func testAllBriefsEndpointReturnsChannelInfo() async throws {
        let json = """
        {"items":[{"id":"brf_1","channelId":"chn_1","title":"t","sections":[],"memorySummary":"m",
                   "createdAt":"2026-11-20T02:01:50.774Z","channelName":"AI 前沿","channelKind":"channel"}],
         "nextCursor":"20"}
        """
        let transport = StubTransport(json: json)
        let client = TestClient.make(transport: transport)

        let page = try await client.allBriefs(cursor: nil, limit: 20)

        XCTAssertEqual(page.items.count, 1)
        // 全量端点自带频道信息，无需回查。
        XCTAssertEqual(page.items.first?.channelName, "AI 前沿")
        XCTAssertEqual(page.items.first?.channelKind, .channel)
        XCTAssertEqual(page.nextCursor, "20")
        XCTAssertEqual(transport.recorded.first?.url.path, "/api/v1/briefs")
    }

    func testAllBriefsSendsPaginationParameters() async throws {
        let transport = StubTransport(json: #"{"items":[],"nextCursor":null}"#)
        let client = TestClient.make(transport: transport)

        _ = try await client.allBriefs(cursor: "40", limit: 20)

        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(transport.recorded.first?.url), resolvingAgainstBaseURL: false)
        )
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.first { $0.name == "cursor" }?.value, "40")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "20")
    }

    func testConnectorsEndpoint() async throws {
        let transport = StubTransport(
            json: #"{"items":[{"id":"cnn_homepage","name":"HN 首页","kind":"rss"}],"nextCursor":null}"#
        )
        let client = TestClient.make(transport: transport)

        let connectors = try await client.connectors()

        XCTAssertEqual(connectors.count, 1)
        XCTAssertEqual(connectors.first?.id, "cnn_homepage")
        XCTAssertEqual(connectors.first?.name, "HN 首页")
        XCTAssertEqual(transport.recorded.first?.url.path, "/api/v1/connectors")
    }

    func testSubscriptionEndpointsUseChannelPaths() async throws {
        let subscriptionJSON = """
        {"id":"sub_1","channelId":"chn_sub","color":"#2E7D5B","createdAt":"2026-11-21T01:00:00.000Z","subscribed":true}
        """
        let transport = StubTransport(json: subscriptionJSON, status: 201)
        let client = TestClient.make(transport: transport)

        try await client.subscribe(channelID: "chn_sub", color: "#2E7D5B")

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/v1/channels/chn_sub/subscribe")
        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["color"])
        XCTAssertEqual(json["color"] as? String, "#2E7D5B")
    }

    func testRepeatedSubscriptionIsIdempotentForClient() async throws {
        // 幂等：服务端重复订阅返回 200 与同一条记录，客户端同样按成功处理。
        let subscriptionJSON = """
        {"id":"sub_1","channelId":"chn_sub","color":"","createdAt":"2026-11-21T01:00:00.000Z","subscribed":true}
        """
        let transport = StubTransport(json: subscriptionJSON, status: 200)
        let client = TestClient.make(transport: transport)

        let dto = try await client.subscribe(channelID: "chn_sub", color: "#2E7D5B")

        XCTAssertEqual(dto.id, "sub_1")
        XCTAssertEqual(dto.channelId, "chn_sub")
        XCTAssertEqual(transport.recorded.count, 1)
    }

    func testUpdateSubscriptionColorPatchesOnlyColor() async throws {
        let channelJSON = try firstChannelObjectJSON()
        let transport = StubTransport(json: String(decoding: channelJSON, as: UTF8.self), status: 200)
        let client = TestClient.make(transport: transport)

        _ = try await client.updateSubscriptionColor(channelID: "chn_sub", color: "#B05A2A")

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.url.path, "/api/v1/channels/chn_sub/subscribe")
        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["color"])
    }

    func testUnsubscribeDeletesSubscriptionEndpoint() async throws {
        let transport = StubTransport(json: """
        {"channelId":"chn_sub","subscribed":false}
        """)
        let client = TestClient.make(transport: transport)

        try await client.unsubscribe(channelID: "chn_sub")

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.url.path, "/api/v1/channels/chn_sub/subscribe")
    }

    func testForkPostsToForkPathAndReturnsOwnChannel() async throws {
        let channelJSON = """
        {"id":"chn_forked","name":"安全观察","prompt":"p","tone":"t","schedule":{},"enabled":true,
         "connectorIds":[],"lastBriefAt":null,"kind":"channel","published":false,
         "owner":"creator","subscribed":false,"subscriptionColor":null,"subscriptionId":null,
         "createdAt":"2026-11-21T01:00:00.000Z","updatedAt":"2026-11-21T01:00:00.000Z"}
        """
        let transport = StubTransport(json: channelJSON, status: 201)
        let client = TestClient.make(transport: transport)

        let channel = try await client.forkChannel(id: "chn_sub")

        XCTAssertEqual(channel.id, "chn_forked")
        XCTAssertTrue(channel.owner.isCreator)
        XCTAssertFalse(channel.published)
        XCTAssertFalse(channel.subscribed)
        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/v1/channels/chn_sub/fork")
    }

    func testDiscoverListSendsDiscoverFlag() async throws {
        let transport = StubTransport(json: """
        {"items":[],"nextCursor":null}
        """)
        let client = TestClient.make(transport: transport)

        _ = try await client.channels(discover: true)

        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.url.path, "/api/v1/channels")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "discover", value: "1")) ?? false)
    }

    func testDefaultListOmitsDiscoverFlag() async throws {
        let transport = StubTransport(json: """
        {"items":[],"nextCursor":null}
        """)
        let client = TestClient.make(transport: transport)

        _ = try await client.channels()

        let request = try XCTUnwrap(transport.recorded.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertFalse(components.queryItems?.contains { $0.name == "discover" } ?? false)
    }

    // MARK: 辅助

    /// 从 channels.json 取出单个频道对象的原始 JSON（PATCH 的响应形状）。
    private func firstChannelObjectJSON() throws -> Data {
        let root = try JSONSerialization.jsonObject(with: try Fixture.data("channels")) as? [String: Any]
        let items = try XCTUnwrap(root?["items"] as? [[String: Any]])
        let first = try XCTUnwrap(items.first)
        return try JSONSerialization.data(withJSONObject: first)
    }
}
