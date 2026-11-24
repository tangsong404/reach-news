import XCTest
@testable import ReachNews

// MARK: - 账号资料
//
// 「我的」页头部只读呈现：用户名回退、缺省邮箱、套餐标识与缺省头像判定。

final class ProfileStoreTests: XCTestCase {
    @MainActor
    private func makeProfile(
        preferences: InMemoryPreferences = InMemoryPreferences(),
        credentials: InMemoryCredentials = InMemoryCredentials()
    ) -> (ProfileStore, SessionStore, InMemoryPreferences) {
        // 不用 raw string：本机 tree-sitter 解析器不支持 #"..."#，会误报语法错误。
        let client = TestClient.make(transport: StubTransport(json: "{\"ok\":true}"), token: nil)
        let session = SessionStore(
            credentials: credentials,
            preferences: preferences,
            makeClient: { _ in client }
        )
        return (ProfileStore(session: session, preferences: preferences), session, preferences)
    }

    @MainActor
    func testPlanIsUltraWhileBackendHasNoField() {
        let (profile, _, _) = makeProfile()

        XCTAssertEqual(profile.plan, .ultra)
        XCTAssertEqual(profile.plan.label, "ultra")
        XCTAssertEqual(profile.plan.labelKey, "me.account.plan.ultra")
    }

    @MainActor
    func testPlanTierHasExactlyThreeValues() {
        XCTAssertEqual(Set(PlanTier.allCases.map(\.label)), Set(["free", "pro", "ultra"]))
    }

    @MainActor
    func testUserNameFallsBackToLastLoginName() {
        let preferences = InMemoryPreferences()
        preferences.lastUserName = "tangsong404"
        let (profile, _, _) = makeProfile(preferences: preferences)

        XCTAssertEqual(profile.userName, "tangsong404")
        XCTAssertFalse(profile.userName.isEmpty)
    }

    @MainActor
    func testUserNamePrefersStoredSessionName() {
        let credentials = InMemoryCredentials(
            token: "token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let preferences = InMemoryPreferences()
        preferences.lastUserName = "stale-name"
        let (profile, session, _) = makeProfile(preferences: preferences, credentials: credentials)

        XCTAssertEqual(session.session?.userName, "")
        // 恢复的会话没有名字，回退到上次登录名，而不是显示空行。
        XCTAssertEqual(profile.userName, "stale-name")
    }

    @MainActor
    func testSignInRecordsNameForColdStart() async {
        let loginJSON = "{\"token\":\"session-abc\",\"expiresAt\":\"2099-01-01T00:00:00.000Z\","
            + "\"user\":{\"id\":\"usr_1\",\"name\":\"tangsong404\"}}"
        let preferences = InMemoryPreferences()
        let client = TestClient.make(transport: StubTransport(json: loginJSON), token: nil)
        let session = SessionStore(
            credentials: InMemoryCredentials(),
            preferences: preferences,
            makeClient: { _ in client }
        )
        let profile = ProfileStore(session: session, preferences: preferences)
        session.username = "tangsong404"
        session.password = "secret"

        let ok = await session.signIn()

        XCTAssertTrue(ok)
        XCTAssertEqual(profile.userName, "tangsong404")
        // 冷启动恢复的会话没有名字，靠这条偏好项回退。
        XCTAssertEqual(preferences.lastUserName, "tangsong404")
    }

    @MainActor
    func testEmailUsesPlaceholderAddress() {
        let (profile, _, _) = makeProfile()

        XCTAssertEqual(profile.email, "name@example.com")
        XCTAssertEqual(ProfileStore.placeholderEmail, "name@example.com")
    }

    @MainActor
    func testAvatarFallsBackToPlaceholderWhileNoBackendImage() {
        let (profile, _, _) = makeProfile()

        // nil 表示界面走缺省头像分支。
        XCTAssertNil(profile.avatarImageName)
    }
}
