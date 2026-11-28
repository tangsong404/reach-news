import XCTest
@testable import ReachNews

final class CollectorSkillTests: XCTestCase {
    private let response = """
    {"id":"channel","name":"Draft","enabled":false,"collectorSkillIds":[],"collectorSkills":[],"collectionStatus":{"available":false,"pausedReason":"collector_skill_required"}}
    """

    func testUnavailableBindingAndIconSurviveDTO() throws {
        let json = """
        {"id":"channel","name":"Old","enabled":false,"connectorIds":["historical"],
         "collectorSkillIds":["gone"],"collectorSkills":[{"id":"gone","name":"Source","available":false,"reason":"skill_disabled","message":"技能停用","iconUrl":"/api/v1/collector-skills/gone/icon.svg?v=icon"}],
         "collectionStatus":{"available":false,"pausedReason":"invalid_collector_skill"}}
        """
        let channel = try JSONDecoder().decode(ChannelDTO.self, from: Data(json.utf8)).toDomain()
        XCTAssertEqual(channel.connectorIDs, ["historical"])
        XCTAssertEqual(channel.collectorSkillIDs, ["gone"])
        XCTAssertFalse(channel.collectorSkills[0].available)
        XCTAssertEqual(channel.collectorSkills[0].message, "技能停用")
        XCTAssertEqual(channel.collectorSkills[0].iconURLPath, "/api/v1/collector-skills/gone/icon.svg?v=icon")
        XCTAssertEqual(channel.collectionStatus?.pausedReason, "invalid_collector_skill")
        XCTAssertFalse(channel.hasUsableCollectorSkills)
    }

    func testPatchNeverContainsLegacyWriteKey() throws {
        let changes = ChannelChanges(enabled: false, collectorSkillIDs: [])
        let body = try JSONEncoder().encode(ChannelPatchBody(changes: changes))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["connectorIds"])
        XCTAssertNil(json["iconUrl"])
        XCTAssertEqual(json["collectorSkillIds"] as? [String], [])
        XCTAssertEqual(json["enabled"] as? Bool, false)
    }

    @MainActor
    func testDisabledDraftCanBeCreatedWithoutSource() async throws {
        let transport = StubTransport(json: response, status: 201)
        let client = TestClient.make(transport: transport)
        let channel = try await client.createChannel(name: "Draft", prompt: "p", tone: "", schedule: Schedule(), collectorSkillIDs: [], enabled: false)
        XCTAssertFalse(channel.enabled)
        let request = try XCTUnwrap(transport.recorded.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["enabled"] as? Bool, false)
        XCTAssertEqual(json["collectorSkillIds"] as? [String], [])
        XCTAssertNil(json["connectorIds"])
    }

    @MainActor
    func testLegacyCreationFailsLocallyInsteadOfWritingOldIDs() async {
        let transport = StubTransport(json: response)
        do {
            _ = try await TestClient.make(transport: transport).createChannel(name: "n", prompt: "p", tone: "", schedule: Schedule(), connectorIDs: ["legacy"])
            XCTFail("Old connector IDs must not be submitted")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .collectorMigrationRequired)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(transport.recorded.isEmpty)
    }

    @MainActor
    func testDirectoryPaginatesNewEndpoint() async throws {
        let transport = StubTransport { request in
            XCTAssertEqual(request.url?.path, "/api/v1/collector-skills")
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value
            let payload: [String: Any] = cursor == nil
                ? ["items": [["id": "one", "name": "First", "available": true]], "nextCursor": "1"]
                : ["items": [["id": "two", "name": "Second", "available": true]], "nextCursor": NSNull()]
            return (200, try JSONSerialization.data(withJSONObject: payload))
        }
        let values = try await TestClient.make(transport: transport).collectorSkills()
        XCTAssertEqual(values.map(\.id), ["one", "two"])
        XCTAssertEqual(transport.recorded.count, 2)
    }

    func testCollectorErrorsKeepCodeAndServerMessage() throws {
        for raw in ["collector_migration_required", "collector_skill_required", "invalid_collector_skill"] {
            let data = try JSONSerialization.data(withJSONObject: ["error": ["code": raw, "message": "服务端说明"]])
            let error = try JSONDecoder().decode(ErrorEnvelope.self, from: data).normalized
            XCTAssertEqual(error.errorCode?.rawValue, raw)
            XCTAssertEqual(error.detailText, "服务端说明")
        }
    }

    @MainActor
    func testBindingDoesNotResumeManuallyPausedChannel() throws {
        var channel = try JSONDecoder().decode(ChannelDTO.self, from: Data(response.utf8)).toDomain()
        channel.enabled = false
        var draft = ChannelDraft(channel: channel)
        draft.collectorSkillIDs = ["approved"]
        let changes = draft.changes(against: channel)
        XCTAssertEqual(changes.collectorSkillIDs, ["approved"])
        XCTAssertNil(changes.enabled)
    }
}
