import XCTest
@testable import ReachNews

// MARK: - 账号资料
//
// 「我的」页头部的水数据来自服务端真实字段。这里覆盖：
// 用户名回退（冷启动不空行）、email 为 null 的占位、tier 原样显示不映射、
// 以及资料随会话清除（退出登录不残留上一账号）。

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

    private func meJSON(
        name: String = "bot",
        email: String? = nil,
        tier: String = "admin",
        avatarUrl: String? = nil,
        channelLimit: Int? = nil
    ) -> String {
        let emailValue = email.map { "\"\($0)\"" } ?? "null"
        let avatarValue = avatarUrl.map { "\"\($0)\"" } ?? "null"
        let limitValue = channelLimit.map(String.init) ?? "null"
        return """
        {"id":"usr_1","name":"\(name)","email":\(emailValue),"tier":"\(tier)","avatarUrl":\(avatarValue),\
        "createdAt":"2026-11-25T03:13:10.477Z","channelCount":0,\
        "capabilities":{"tier":"\(tier)","ask":true,"briefImages":true,"channelLimit":\(limitValue)}}
        """
    }

    @MainActor
    func testTierIsShownVerbatimWithoutMapping() {
        let preferences = InMemoryPreferences()
        let (profile, session, _) = makeProfile(preferences: preferences)

        // 实测 admin 账号：必须原样显示，不能映射成 ultra。
        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: nil, tier: "admin", avatarURLPath: nil, channelCount: 0)
        )

        XCTAssertEqual(profile.planLabel, "admin")
    }

    @MainActor
    func testNoProTierExistsInModel() {
        let preferences = InMemoryPreferences()
        let (profile, session, _) = makeProfile(preferences: preferences)

        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: nil, tier: "free", avatarURLPath: nil, channelCount: 0)
        )
        XCTAssertEqual(profile.planLabel, "free")

        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: nil, tier: "ultra", avatarURLPath: nil, channelCount: 0)
        )
        XCTAssertEqual(profile.planLabel, "ultra")
    }

    @MainActor
    func testNilEmailProducesPlaceholderNotBlank() {
        let preferences = InMemoryPreferences()
        let (profile, session, _) = makeProfile(preferences: preferences)

        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: nil, tier: "admin", avatarURLPath: nil, channelCount: 0)
        )

        // nil 表示「没有邮箱」，界面据此显示本地化的占位文案。
        XCTAssertNil(profile.email)
    }

    @MainActor
    func testEmptyEmailIsTreatedAsAbsent() {
        let preferences = InMemoryPreferences()
        let (profile, session, _) = makeProfile(preferences: preferences)

        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: "   ", tier: "admin", avatarURLPath: nil, channelCount: 0)
        )

        XCTAssertNil(profile.email)
    }

    @MainActor
    func testUserNamePrefersServerProfile() {
        let preferences = InMemoryPreferences()
        preferences.lastUserName = "stale-name"
        let (profile, session, _) = makeProfile(preferences: preferences)

        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: nil, tier: "admin", avatarURLPath: nil, channelCount: 0)
        )

        XCTAssertEqual(profile.userName, "bot")
    }

    @MainActor
    func testUserNameFallsBackToLastLoginNameBeforeProfileArrives() {
        let preferences = InMemoryPreferences()
        preferences.lastUserName = "tangsong404"
        let (profile, _, _) = makeProfile(preferences: preferences)

        // 冷启动、/me 还没回来时也不能空行。
        XCTAssertEqual(profile.userName, "tangsong404")
    }

    @MainActor
    func testUserNameNeverEmptyWhenNothingKnown() {
        let (profile, _, _) = makeProfile()

        XCTAssertFalse(profile.userName.isEmpty)
        XCTAssertEqual(profile.userName, ProfileStore.unknownPlaceholder)
    }

    @MainActor
    func testSignOutClearsProfileSoNextAccountDoesNotSeeIt() async {
        let preferences = InMemoryPreferences()
        let (profile, session, _) = makeProfile(preferences: preferences)

        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: "b@example.com", tier: "admin", avatarURLPath: nil, channelCount: 0)
        )
        XCTAssertEqual(profile.userName, "bot")

        await session.signOut()

        // 退出后资料必须被清掉：否则换账号会看到上一个账号的头部。
        XCTAssertNil(session.profile)
        XCTAssertNotEqual(profile.userName, "bot")
    }

    @MainActor
    func testAvatarURLIsNilWithoutAvatarPath() {
        let preferences = InMemoryPreferences()
        let (profile, session, _) = makeProfile(preferences: preferences)

        session.applyProfileForTesting(
            UserProfile(id: "usr_1", name: "bot", email: nil, tier: "admin", avatarURLPath: nil, channelCount: 0)
        )

        XCTAssertNil(profile.avatarURL)
    }

    @MainActor
    func testAvatarURLIsResolvedAgainstBaseURL() {
        let preferences = InMemoryPreferences()
        let (profile, session, _) = makeProfile(preferences: preferences)

        session.applyProfileForTesting(
            UserProfile(
                id: "usr_1",
                name: "bot",
                email: nil,
                tier: "admin",
                avatarURLPath: "/api/v1/users/usr_1/avatar",
                channelCount: 0
            )
        )

        let url = profile.avatarURL
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.hasSuffix("/api/v1/users/usr_1/avatar") == true)
    }
}

// MARK: - 档位能力

final class UserCapabilitiesTests: XCTestCase {
    func testNilLimitMeansUnlimited() {
        let caps = UserCapabilities(tier: "admin", ask: true, briefImages: true, channelLimit: nil)

        XCTAssertFalse(caps.reachedChannelLimit(currentCount: 999))
    }

    func testFreeTierReachesLimitAtOne() {
        let caps = UserCapabilities(tier: "free", ask: true, briefImages: false, channelLimit: 1)

        XCTAssertFalse(caps.reachedChannelLimit(currentCount: 0))
        XCTAssertTrue(caps.reachedChannelLimit(currentCount: 1))
    }
}
