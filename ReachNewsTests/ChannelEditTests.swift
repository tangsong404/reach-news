import XCTest
@testable import ReachNews

// MARK: - 频道编辑

final class ChannelEditTests: XCTestCase {
    func testEmptyDraftProducesNoChanges() {
        let channel = makeChannel()
        let draft = ChannelDraft(channel: channel)
        let changes = draft.changes(against: channel)

        XCTAssertTrue(changes.isEmpty)
        XCTAssertTrue(changes.changedFieldNames.isEmpty)
    }

    func testOnlyChangedFieldsAreSubmitted() {
        let channel = makeChannel()
        var draft = ChannelDraft(channel: channel)
        draft.name = "新名字"
        draft.tone = "更克制"

        let changes = draft.changes(against: channel)

        XCTAssertFalse(changes.isEmpty)
        XCTAssertEqual(changes.name, "新名字")
        XCTAssertEqual(changes.tone, "更克制")
        // 未改动的字段不出现，因此不会被提交。
        XCTAssertNil(changes.prompt)
        XCTAssertNil(changes.schedule)
        XCTAssertNil(changes.enabled)
        XCTAssertEqual(changes.changedFieldNames, ["name", "tone"])
    }

    func testScheduleChangeIsDetected() {
        let channel = makeChannel()
        var draft = ChannelDraft(channel: channel)
        var schedule = draft.schedule
        schedule.addTime("18:00", to: Schedule.Weekday.all[0])
        draft.schedule = schedule

        let changes = draft.changes(against: channel)
        XCTAssertNotNil(changes.schedule)
        XCTAssertEqual(changes.changedFieldNames, ["schedule"])
    }

    func testPatchBodyOmitsUnchangedKeys() throws {
        let channel = makeChannel()
        var draft = ChannelDraft(channel: channel)
        draft.enabled = false

        let body = ChannelPatchBody(changes: draft.changes(against: channel))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json.keys.sorted(), ["enabled"])
        XCTAssertEqual(json["enabled"] as? Bool, false)
    }

    func testPatchBodyEncodesScheduleWithWeekdayKeys() throws {
        let channel = makeChannel()
        var draft = ChannelDraft(channel: channel)
        draft.schedule = Schedule(timesByWeekday: ["mon": ["08:00"], "fri": ["18:00"]])

        let body = ChannelPatchBody(changes: draft.changes(against: channel))
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let schedule = try XCTUnwrap(json["schedule"] as? [String: [String]])

        // 只提交配置过的星期。
        XCTAssertEqual(schedule.keys.sorted(), ["fri", "mon"])
        XCTAssertEqual(schedule["mon"], ["08:00"])
        XCTAssertEqual(schedule["fri"], ["18:00"])
    }

    @MainActor
    func testBusyErrorIsRecognisedAsRunning() async {
        let channel = makeChannel()
        let transport = StubTransport(json: #"{"error":{"code":"busy","message":"Channel has a run in progress"}}"#, status: 409)
        let client = TestClient.make(transport: transport)
        let editor = ChannelEditor(channel: channel, client: client)
        editor.draft.name = "改过的名字"

        let result = await editor.save()

        XCTAssertNil(result)
        XCTAssertTrue(editor.isBlockedByRunning)
        // 409 之后已填内容必须保留。
        XCTAssertEqual(editor.draft.name, "改过的名字")
        XCTAssertFalse(editor.didSave)
    }

    @MainActor
    func testSaveSubmitsPatchToChannelEndpoint() async throws {
        let channel = makeChannel()
        // PATCH 返回单个频道对象：从 channels.json 取出第一项的原始 JSON。
        let responseBody = try firstChannelObjectJSON()
        let transport = StubTransport(handler: { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/channels/\(channel.id)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return (200, responseBody)
        })
        let client = TestClient.make(transport: transport)
        let editor = ChannelEditor(channel: channel, client: client)
        editor.draft.enabled = false

        _ = await editor.save()

        let body = try XCTUnwrap(transport.recorded.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["enabled"])
    }

    // MARK: 辅助

    /// 从 channels.json 取出单个频道对象的原始 JSON（PATCH 的响应形状）。
    private func firstChannelObjectJSON() throws -> Data {
        let root = try JSONSerialization.jsonObject(with: try Fixture.data("channels")) as? [String: Any]
        let items = try XCTUnwrap(root?["items"] as? [[String: Any]])
        let first = try XCTUnwrap(items.first)
        return try JSONSerialization.data(withJSONObject: first)
    }

    private func makeChannel() -> Channel {
        Channel(
            id: "chn_test",
            name: "AI 前沿",
            prompt: "总结今天的进展",
            tone: "简洁中文",
            schedule: Schedule(timesByWeekday: ["mon": ["08:00"]]),
            enabled: true,
            connectorIDs: ["cnn_homepage"],
            connectors: [ChannelConnector(id: "cnn_homepage", name: "HN 首页", kind: "hn", removed: false)],
            lastBriefAt: nil,
            kind: .channel,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

// MARK: - 删除频道（A43 / A44）

final class ChannelDeleteTests: XCTestCase {
    @MainActor
    private func makeStore(_ transport: StubTransport) -> ChannelStore {
        ChannelStore(client: TestClient.make(transport: transport))
    }

    @MainActor
    func testDeleteCallsDeleteEndpoint() async {
        let transport = StubTransport(json: #"{"id":"chn_1","deleted":true}"#)
        let store = makeStore(transport)

        let ok = await store.delete("chn_1")

        XCTAssertTrue(ok)
        let request = transport.recorded.first
        XCTAssertEqual(request?.method, "DELETE")
        XCTAssertEqual(request?.url.path, "/api/v1/channels/chn_1")
    }

    @MainActor
    func testDeleteRemovesChannelFromList() async {
        let channelsJSON = """
        {"items":[{"id":"chn_1","name":"A","prompt":"","tone":"","schedule":{},"enabled":true,
                   "connectorIds":[],"lastBriefAt":null,"kind":"channel",
                   "createdAt":"2026-11-20T02:01:50.774Z","updatedAt":"2026-11-20T02:01:50.774Z"}],
         "nextCursor":null}
        """
        var callCount = 0
        let transport = StubTransport { request in
            callCount += 1
            if request.httpMethod == "DELETE" {
                return (200, Data(#"{"id":"chn_1","deleted":true}"#.utf8))
            }
            return (200, Data(channelsJSON.utf8))
        }
        let store = makeStore(transport)
        await store.load()
        XCTAssertEqual(store.channels.count, 1)

        _ = await store.delete("chn_1")

        XCTAssertTrue(store.channels.isEmpty)
    }

    @MainActor
    func testNotFoundIsTreatedAsAlreadyDeleted() async {
        // 别人的频道或已删除的频道都返回 404：按已删除处理，不报错。
        let transport = StubTransport(
            json: #"{"error":{"code":"not_found","message":"Channel not found"}}"#,
            status: 404
        )
        let store = makeStore(transport)

        let ok = await store.delete("chn_missing")

        XCTAssertTrue(ok)
        XCTAssertNil(store.createError)
    }

    @MainActor
    func testBusyDoesNotDelete() async {
        // 有运行在跑返回 409：不删除，并把原因留给界面提示。
        let transport = StubTransport(
            json: #"{"error":{"code":"busy","message":"Channel is not idle"}}"#,
            status: 409
        )
        let store = makeStore(transport)

        let ok = await store.delete("chn_busy")

        XCTAssertFalse(ok)
        XCTAssertEqual(store.createError, .busy("Channel is not idle"))
    }

    @MainActor
    func testDeleteSendsAuthorization() async {
        let transport = StubTransport(json: #"{"id":"chn_1","deleted":true}"#)
        let store = makeStore(transport)

        _ = await store.delete("chn_1")

        XCTAssertEqual(transport.recorded.first?.authorization, "Bearer test-token")
    }
}

// MARK: - 连接器编辑与新建频道（2026-11-21 第二轮）

final class ChannelConnectorTests: XCTestCase {
    @MainActor
    private func makeChannel(connectorIDs: [String] = ["cnn_homepage"]) -> Channel {
        Channel(
            id: "chn_test",
            name: "AI 前沿",
            prompt: "总结今天的进展",
            tone: "简洁中文",
            schedule: Schedule(timesByWeekday: ["mon": ["08:00"]]),
            enabled: true,
            connectorIDs: connectorIDs,
            connectors: connectorIDs.map {
                ChannelConnector(id: $0, name: "HN 首页", kind: "hn", removed: false)
            },
            lastBriefAt: nil,
            kind: .channel,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            collectorSkillIDs: connectorIDs
        )
    }

    @MainActor
    func testChannelDTOExposesConnectorNames() async throws {
        let json = """
        {"items":[{"id":"chn_1","name":"A","prompt":"p","tone":"","schedule":{},"enabled":true,
                   "connectorIds":["cnn_homepage"],"connectors":[{"id":"cnn_homepage","name":"HN 首页","kind":"hn","removed":false}],
                   "lastBriefAt":null,"kind":"channel",
                   "createdAt":"2026-11-20T02:01:50.774Z","updatedAt":"2026-11-20T02:01:50.774Z"}],
         "nextCursor":null}
        """
        let client = TestClient.make(transport: StubTransport(json: json))
        let page = try await client.channels()

        let channel = try XCTUnwrap(page.items.first)
        XCTAssertEqual(channel.connectors.count, 1)
        XCTAssertEqual(channel.connectors.first?.displayName, "HN 首页")
        XCTAssertFalse(channel.connectors.first?.isUnavailable ?? true)
    }

    @MainActor
    func testRemovedConnectorIsMarkedUnavailable() async throws {
        // 连接器已从代码移除时 name 为 null：应提示失效，而不是显示 UUID。
        let json = """
        {"items":[{"id":"chn_1","name":"A","prompt":"p","tone":"","schedule":{},"enabled":true,
                   "connectorIds":["gone"],"connectors":[{"id":"gone","name":null,"kind":null,"removed":true}],
                   "lastBriefAt":null,"kind":"channel",
                   "createdAt":"2026-11-20T02:01:50.774Z","updatedAt":"2026-11-20T02:01:50.774Z"}],
         "nextCursor":null}
        """
        let client = TestClient.make(transport: StubTransport(json: json))
        let page = try await client.channels()
        let connector = try XCTUnwrap(page.items.first?.connectors.first)

        XCTAssertTrue(connector.isUnavailable)
        XCTAssertEqual(connector.displayName, "gone")
    }

    @MainActor
    func testConnectorChangeIsSubmittedAsWholeReplacement() async throws {
        let channel = makeChannel()
        var draft = ChannelDraft(channel: channel)
        draft.collectorSkillIDs = ["cnn_github_trending", "cnn_homepage"]

        let changes = draft.changes(against: channel)

        XCTAssertNotNil(changes.collectorSkillIDs)
        XCTAssertEqual(changes.changedFieldNames, ["collectorSkillIds"])
        let body = ChannelPatchBody(changes: changes)
        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["collectorSkillIds"])
    }

    @MainActor
    func testClearingConnectorsIsAContractualChange() async throws {
        let channel = makeChannel()
        var draft = ChannelDraft(channel: channel)
        draft.collectorSkillIDs = []

        let changes = draft.changes(against: channel)
        XCTAssertEqual(changes.collectorSkillIDs, [])

        let data = try JSONEncoder().encode(ChannelPatchBody(changes: changes))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["collectorSkillIds"] as? [String], [])
    }

    @MainActor
    func testConnectorOrderDoesNotProduceChange() async throws {
        let channel = makeChannel()
        var draft = ChannelDraft(channel: channel)
        // 同样的集合、不同顺序不算改动。
        draft.collectorSkillIDs = channel.collectorSkillIDs.reversed()

        XCTAssertTrue(draft.changes(against: channel).isEmpty)
    }

    @MainActor
    func testCreateChannelPostsContractBody() async throws {
        let responseJSON = """
        {"id":"chn_new","name":"新频道","prompt":"p","tone":"t","schedule":{"mon":["08:00"]},
         "enabled":true,"connectorIds":["cnn_homepage"],
         "connectors":[{"id":"cnn_homepage","name":"HN 首页","kind":"hn","removed":false}],
         "lastBriefAt":null,"kind":"channel",
         "createdAt":"2026-11-20T02:01:50.774Z","updatedAt":"2026-11-20T02:01:50.774Z"}
        """
        let transport = StubTransport(json: responseJSON, status: 201)
        let client = TestClient.make(transport: transport)

        let channel = try await client.createChannel(
            name: "新频道",
            prompt: "p",
            tone: "t",
            schedule: Schedule(timesByWeekday: ["mon": ["08:00"]]),
            collectorSkillIDs: ["skl_homepage"]
        )

        XCTAssertEqual(channel.id, "chn_new")
        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/v1/channels")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "新频道")
        XCTAssertEqual(json["collectorSkillIds"] as? [String], ["skl_homepage"])
        let schedule = try XCTUnwrap(json["schedule"] as? [String: [String]])
        XCTAssertEqual(schedule["mon"], ["08:00"])
    }

    @MainActor
    func testInvalidConnectorErrorIsSurfaced() async {
        let transport = StubTransport(
            json: #"{"error":{"code":"invalid_collector_skill","message":"采集技能不可用"}}"#,
            status: 400
        )
        let store = ChannelStore(client: TestClient.make(transport: transport))

        let created = await store.create(
            name: "n", prompt: "p", tone: "", schedule: Schedule(), collectorSkillIDs: ["x"]
        )

        XCTAssertNil(created)
        XCTAssertEqual(store.createError, .collectorConfiguration(.invalidCollectorSkill, "采集技能不可用"))
    }
}

// MARK: - 只改颜色也能保存

final class ColorOnlySaveTests: XCTestCase {
    private func firstChannelJSON() throws -> Data {
        let root = try JSONSerialization.jsonObject(with: try Fixture.data("channels")) as? [String: Any]
        let items = try XCTUnwrap(root?["items"] as? [[String: Any]])
        return try JSONSerialization.data(withJSONObject: try XCTUnwrap(items.first))
    }

    @MainActor
    private func makeChannel() -> Channel {
        Channel(
            id: "chn_color",
            name: "AI 前沿",
            prompt: "p",
            tone: "t",
            schedule: Schedule(timesByWeekday: ["mon": ["08:00"]]),
            enabled: true,
            connectorIDs: ["cnn_homepage"],
            connectors: [ChannelConnector(id: "cnn_homepage", name: "HN 首页", kind: "hn", removed: false)],
            lastBriefAt: nil,
            kind: .channel,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @MainActor
    func testColorOnlyChangeEnablesSave() {
        let channel = makeChannel()
        let transport = StubTransport(json: "{}")
        let editor = ChannelEditor(channel: channel, client: TestClient.make(transport: transport))

        XCTAssertFalse(editor.hasChanges)

        editor.initialColorIndex = 1
        editor.currentColorIndex = 1
        XCTAssertFalse(editor.hasChanges)

        // 只换颜色：字段没有变化，但保存应当可用。
        editor.currentColorIndex = 4
        XCTAssertTrue(editor.hasColorChange)
        XCTAssertTrue(editor.hasChanges)
        XCTAssertTrue(editor.changes.isEmpty)
    }

    @MainActor
    func testColorOnlySaveSkipsNetworkRequest() async {
        let channel = makeChannel()
        let transport = StubTransport(json: "{}")
        let editor = ChannelEditor(channel: channel, client: TestClient.make(transport: transport))
        editor.initialColorIndex = 1
        editor.currentColorIndex = 5

        let result = await editor.save()

        XCTAssertNotNil(result)
        XCTAssertTrue(editor.didSave)
        // 颜色只在本地，不应发出 PATCH。
        XCTAssertTrue(transport.recorded.isEmpty)
    }

    @MainActor
    func testFieldChangeStillPostsPatch() async throws {
        let channel = makeChannel()
        // PATCH 返回单个频道对象；直接取 channels.json 里的原始 JSON。
        let body = try firstChannelJSON()
        let transport = StubTransport(handler: { _ in (200, body) })
        let editor = ChannelEditor(channel: channel, client: TestClient.make(transport: transport))
        editor.initialColorIndex = 1
        editor.currentColorIndex = 1
        editor.draft.name = "改了名字"

        _ = await editor.save()

        XCTAssertEqual(transport.recorded.first?.method, "PATCH")
    }
}
