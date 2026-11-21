import XCTest
@testable import ReachNews

// MARK: - DTO 解码
//
// 用仓库里的 Fixtures 验证真实形状。后端已统一 camelCase，
// 但仍保留对旧 snake_case 与整数 enabled 的兼容解析。

final class DTODecodingTests: XCTestCase {
    func testChannelFixtureDecodesAllFields() throws {
        let data = try Fixture.data("channels")
        let envelope = try JSONDecoder().decode(PageEnvelope<ChannelDTO>.self, from: data)
        XCTAssertFalse(envelope.items.isEmpty)

        let channels = envelope.items.map { $0.toDomain() }
        let first = try XCTUnwrap(channels.first)

        XCTAssertEqual(first.name, "AI 前沿")
        XCTAssertTrue(first.enabled)
        XCTAssertEqual(first.kind, .channel)
        XCTAssertEqual(first.schedule.times(for: Schedule.Weekday.all[0]), ["08:00"])
        XCTAssertEqual(first.connectorIDs.count, 2)
        XCTAssertNotNil(first.lastBriefAt)
        XCTAssertEqual(first.createdAt.timeIntervalSince1970, 1790910862.001, accuracy: 0.01)
    }

    func testChannelFixtureCoversNullLastBriefAndEmptyConnectors() throws {
        let data = try Fixture.data("channels")
        let envelope = try JSONDecoder().decode(PageEnvelope<ChannelDTO>.self, from: data)
        let channels = envelope.items.map { $0.toDomain() }

        // 样本必须覆盖 lastBriefAt: null 与 connectorIds: []（client-contract 的 Fixture 要求）。
        XCTAssertTrue(channels.contains { $0.lastBriefAt == nil })
        XCTAssertTrue(channels.contains { $0.connectorIDs.isEmpty })
    }

    func testBriefFixtureDecodesSectionsAndEntries() throws {
        let data = try Fixture.data("briefs")
        let envelope = try JSONDecoder().decode(PageEnvelope<BriefDTO>.self, from: data)
        let brief = try XCTUnwrap(envelope.items.map { $0.toDomain() }.first)

        XCTAssertEqual(brief.title, "模型竞赛进入下半场：三家同时放出长上下文版本")
        XCTAssertEqual(brief.sections.count, 3)
        XCTAssertEqual(brief.sections.first?.title, "重点")
        XCTAssertEqual(brief.sections.first?.entries.count, 2)
        XCTAssertEqual(brief.sections.first?.entries.first?.materialIDs.count, 3)
        // 素材数按 materialIds 去重计数（该期 3 个分组共 10 个不重复素材）。
        XCTAssertEqual(brief.materialCount, 10)
        XCTAssertFalse(brief.memorySummary.isEmpty)
    }

    func testBriefWithMultipleMaterialsPerEntry() throws {
        let data = try Fixture.data("briefs")
        let envelope = try JSONDecoder().decode(PageEnvelope<BriefDTO>.self, from: data)
        let briefs = envelope.items.map { $0.toDomain() }

        // 至少一条条目引用多个素材。
        let hasMulti = briefs.contains { brief in
            brief.sections.contains { section in
                section.entries.contains { $0.materialIDs.count > 1 }
            }
        }
        XCTAssertTrue(hasMulti)
        // 至少一期有多个分组。
        XCTAssertTrue(briefs.contains { $0.sections.count > 1 })
    }

    func testMaterialFixtureKeepsContentButNeverRendersIt() throws {
        let data = try Fixture.data("materials")
        let envelope = try JSONDecoder().decode(PageEnvelope<MaterialDTO>.self, from: data)
        let materials = envelope.items.compactMap { $0.toDomain() }

        XCTAssertFalse(materials.isEmpty)
        let first = try XCTUnwrap(materials.first)
        XCTAssertEqual(first.host, "news.ycombinator.com")
        // content 是原始文件内容，解析保留但不展示。
        XCTAssertFalse(first.content.isEmpty)
    }

    func testRunFixtureDecodesStatesAndMissedReasons() throws {
        let data = try Fixture.data("runs")
        let envelope = try JSONDecoder().decode(PageEnvelope<RunDTO>.self, from: data)
        let runs = envelope.items.map { $0.toDomain() }

        XCTAssertTrue(runs.contains { $0.state == .published })
        XCTAssertTrue(runs.contains { $0.state == .missed })
        XCTAssertTrue(runs.contains { $0.state == .failed })

        let missed = runs.first { $0.state == .missed }
        XCTAssertEqual(missed?.missedReason, .noMaterial)
        // missedReason 只在 missed / failed 有意义。
        XCTAssertNil(runs.first { $0.state == .published }?.missedReason)
    }

    func testCursorFixtureDecodesLegacySnakeCase() throws {
        // 旧样本仍是 snake_case + 整数 enabled；灰度期间必须还能解析。
        let data = try Fixture.data("cursor")
        let payload = try JSONDecoder().decode(CursorDTO.self, from: data).toDomain()

        XCTAssertFalse(payload.briefs.isEmpty)
        XCTAssertFalse(payload.channels.isEmpty)
        XCTAssertEqual(payload.briefs.first?.channelID.hasPrefix("chn_"), true)
        XCTAssertTrue(payload.channels.allSatisfy { $0.enabled == true || $0.enabled == false })
        XCTAssertNotNil(payload.latestBriefAt)
    }

    func testCursorDecodesNewCamelCaseShape() throws {
        // 后端 2026-11-21 起返回 camelCase + 布尔。
        let json = """
        {"briefs":[{"id":"brf_1","channelId":"chn_1","title":"t","createdAt":"2026-11-20T02:01:50.774Z"}],
         "channels":[{"id":"chn_1","name":"AI","enabled":true,"updatedAt":"2026-11-20T02:01:50.774Z"}]}
        """
        let payload = try JSONDecoder().decode(CursorDTO.self, from: Data(json.utf8)).toDomain()

        XCTAssertEqual(payload.briefs.first?.channelID, "chn_1")
        XCTAssertEqual(payload.channels.first?.enabled, true)
        XCTAssertEqual(payload.channels.first?.name, "AI")
    }

    func testAskFixtureNormalizesSnakeCaseCreatedAt() throws {
        let data = try Fixture.data("ask")
        let envelope = try JSONDecoder().decode(PageEnvelope<AskTurnDTO>.self, from: data)
        let turns = envelope.items.map { $0.toDomain() }

        XCTAssertFalse(turns.isEmpty)
        XCTAssertEqual(turns.first?.role, .user)
        XCTAssertTrue(turns.contains { $0.role == .assistant })
        // created_at 已转成 Date，不是字符串。
        XCTAssertGreaterThan(turns.first?.createdAt.timeIntervalSince1970 ?? 0, 1_700_000_000)
    }

    func testErrorFixtureCoversAllKnownCodes() throws {
        let data = try Fixture.data("errors")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errors = try XCTUnwrap(json?["errors"] as? [[String: Any]])
        let codes = errors.compactMap { ($0["error"] as? [String: Any])?["code"] as? String }

        let known: Set<String> = [
            "unauthorized", "not_found", "invalid_input", "busy", "bad_request", "internal_error"
        ]
        XCTAssertEqual(Set(codes), known)
    }

    func testFlexibleBoolAcceptsIntegersAndBooleans() throws {
        let payload = Data(#"{"a":1,"b":0,"c":true,"d":false}"#.utf8)
        struct Wrapper: Decodable {
            let a: FlexibleBool
            let b: FlexibleBool
            let c: FlexibleBool
            let d: FlexibleBool
        }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: payload)
        XCTAssertTrue(decoded.a.value)
        XCTAssertFalse(decoded.b.value)
        XCTAssertTrue(decoded.c.value)
        XCTAssertFalse(decoded.d.value)
    }

    func testTimestampParsingHandlesMillisecondsAndPlainSeconds() {
        let withMillis = JSONDate.parse("2026-11-20T02:01:50.774Z")
        let withoutMillis = JSONDate.parse("2026-11-20T02:01:50Z")

        XCTAssertNotNil(withMillis)
        XCTAssertNotNil(withoutMillis)
        XCTAssertEqual(withMillis!.timeIntervalSince1970, 1795140110.774, accuracy: 0.01)
        XCTAssertNil(JSONDate.parse(nil))
        XCTAssertNil(JSONDate.parse(""))
        XCTAssertNil(JSONDate.parse("not-a-date"))
    }
}
