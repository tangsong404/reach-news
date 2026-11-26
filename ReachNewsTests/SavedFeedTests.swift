import XCTest
@testable import ReachNews

// MARK: - 收藏数据源
//
// 收藏页按 ID 自己拉取，不依赖首页列表——这是修复「收藏凭空消失」的核心。
// 这里覆盖：按 ID 取回、单条失败不影响其他、取消后移除。

final class SavedFeedTests: XCTestCase {

    private func briefJSON(id: String, title: String) -> String {
        """
        {"id":"\(id)","channelId":"ch1","title":"\(title)",\
        "summary":null,"body":null,"sections":[],"memorySummary":"",\
        "createdAt":"2026-11-25T03:13:10.477Z","channelName":"频道","channelKind":"channel"}
        """
    }

    @MainActor
    func testLoadsSavedBriefsByIDNotFromFeedList() async {
        // 关键：首页 store 里没有这些日报，收藏页仍要能取到。
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/briefs/b1") {
                return (200, Data(self.briefJSON(id: "b1", title: "已收藏的日报").utf8))
            }
            return (404, Data("{\"error\":{\"code\":\"not_found\",\"message\":\"x\"}}".utf8))
        }
        let client = TestClient.make(transport: transport)
        let store = SavedFeedStore(client: client)

        await store.load(ids: ["b1"])

        XCTAssertEqual(store.briefs(for: ["b1"]).map(\.id), ["b1"])
        XCTAssertEqual(store.briefs(for: ["b1"]).first?.title, "已收藏的日报")
        XCTAssertTrue(transport.recorded.contains { $0.url.path.hasSuffix("/briefs/b1") })
    }

    @MainActor
    func testOneFailureDoesNotHideOthers() async {
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/briefs/ok") {
                return (200, Data(self.briefJSON(id: "ok", title: "可取的").utf8))
            }
            return (500, Data("{\"error\":{\"code\":\"internal_error\",\"message\":\"boom\"}}".utf8))
        }
        let client = TestClient.make(transport: transport)
        let store = SavedFeedStore(client: client)

        await store.load(ids: ["ok", "bad"])

        XCTAssertEqual(store.briefs(for: ["ok", "bad"]).map(\.id), ["ok"])
        XCTAssertTrue(store.didFail("bad"))
        XCTAssertFalse(store.didFail("ok"))
    }

    @MainActor
    func testForgetRemovesImmediately() async {
        let transport = StubTransport(json: briefJSON(id: "b1", title: "t"))
        let client = TestClient.make(transport: transport)
        let store = SavedFeedStore(client: client)

        await store.load(ids: ["b1"])
        XCTAssertEqual(store.briefs(for: ["b1"]).count, 1)

        store.forget(id: "b1")

        // 取消收藏后立即消失，不等下一次刷新。
        XCTAssertTrue(store.briefs(for: ["b1"]).isEmpty)
    }

    @MainActor
    func testSortedNewestFirst() async {
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            if id == "old" {
                let json = self.briefJSON(id: "old", title: "旧").replacingOccurrences(
                    of: "2026-11-25T03:13:10.477Z", with: "2026-11-20T03:13:10.477Z"
                )
                return (200, Data(json.utf8))
            }
            return (200, Data(self.briefJSON(id: "new", title: "新").utf8))
        }
        let client = TestClient.make(transport: transport)
        let store = SavedFeedStore(client: client)

        await store.load(ids: ["old", "new"])

        XCTAssertEqual(store.briefs(for: ["old", "new"]).map(\.id), ["new", "old"])
    }
}

// MARK: - 外观偏好

final class AppearanceTests: XCTestCase {

    @MainActor
    func testDefaultsWhenNothingStored() {
        let preferences = InMemoryPreferences()
        let store = AppearanceStore(preferences: preferences)

        XCTAssertEqual(store.style, .editorial)
        XCTAssertEqual(store.tint, .ink)
    }

    @MainActor
    func testSelectionPersistsToPreferences() {
        let preferences = InMemoryPreferences()
        let store = AppearanceStore(preferences: preferences)

        store.select(style: .plain)
        store.select(tint: .emerald)

        XCTAssertEqual(preferences.readerStyle, "plain")
        XCTAssertEqual(preferences.themeTint, "emerald")

        // 重建后仍保持选择：模拟重启。
        let restored = AppearanceStore(preferences: preferences)
        XCTAssertEqual(restored.style, .plain)
        XCTAssertEqual(restored.tint, .emerald)
    }

    @MainActor
    func testInvalidStoredValueFallsBackToDefault() {
        let preferences = InMemoryPreferences()
        preferences.readerStyle = "nonsense"
        preferences.themeTint = "nonsense"

        let store = AppearanceStore(preferences: preferences)

        XCTAssertEqual(store.style, .editorial)
        XCTAssertEqual(store.tint, .ink)
    }

    func testTintCoversSixOptions() {
        XCTAssertEqual(ThemeTint.allCases.count, 6)
        XCTAssertEqual(Set(ThemeTint.allCases.map(\.rawValue)).count, 6)
    }

    func testStyleCoversTwoOptions() {
        XCTAssertEqual(ReaderStyle.allCases, [.editorial, .plain])
    }
}
