import XCTest
@testable import ReachNews

// MARK: - 分页参数

final class PaginationTests: XCTestCase {
    func testLimitIsAlwaysWithinContract() {
        // 契约：缺省/0/非数字 → 20；负数 → 1；>100 → 100。
        // 客户端从不主动传 0、负数或 >100。
        XCTAssertEqual(Pagination.sanitizedLimit(20), 20)
        XCTAssertEqual(Pagination.sanitizedLimit(1), 1)
        XCTAssertEqual(Pagination.sanitizedLimit(100), 100)
        XCTAssertEqual(Pagination.sanitizedLimit(101), 100)
        XCTAssertEqual(Pagination.sanitizedLimit(1_000), 100)
        // 客户端不发送 0 或负数：回落到默认值而不是让服务端夹成 1。
        XCTAssertEqual(Pagination.sanitizedLimit(0), Pagination.defaultLimit)
        XCTAssertEqual(Pagination.sanitizedLimit(-5), Pagination.defaultLimit)
    }

    func testNegativeCursorIsNeverUsed() {
        // cursor=-5 返回空页却给出非空 nextCursor，属服务端缺陷：客户端不传、也不缓存。
        XCTAssertNil(Pagination.sanitizedCursor("-5"))
        XCTAssertNil(Pagination.sanitizedCursor("-1"))
        XCTAssertNil(Pagination.sanitizedCursor("abc"))
        XCTAssertNil(Pagination.sanitizedCursor(nil))
        XCTAssertNil(Pagination.sanitizedCursor(""))
        XCTAssertEqual(Pagination.sanitizedCursor("0"), "0")
        XCTAssertEqual(Pagination.sanitizedCursor("40"), "40")
    }

    func testQueryItemsOmitInvalidCursor() {
        let items = Pagination.queryItems(cursor: "-5", limit: 20)
        XCTAssertEqual(items.map(\.name), ["limit"])
        XCTAssertEqual(items.first?.value, "20")

        let withCursor = Pagination.queryItems(cursor: "20", limit: 40)
        XCTAssertEqual(withCursor.map(\.name), ["limit", "cursor"])
        XCTAssertEqual(withCursor.last?.value, "20")
    }

    func testZeroCursorIsNotSent() {
        let items = Pagination.queryItems(cursor: "0", limit: 20)
        XCTAssertEqual(items.map(\.name), ["limit"])
    }

    func testEndpointsBuildContractPaths() {
        XCTAssertEqual(Endpoint.health.path, "/health")
        XCTAssertEqual(Endpoint.channels(cursor: nil, limit: 20).path, "/api/v1/channels")
        XCTAssertEqual(Endpoint.briefs(channelID: "chn_1", cursor: nil, limit: 20).path, "/api/v1/channels/chn_1/briefs")
        XCTAssertEqual(Endpoint.brief(id: "brf_1").path, "/api/v1/briefs/brf_1")
        XCTAssertEqual(
            Endpoint.material(briefID: "brf_1", materialID: "itm_1").path,
            "/api/v1/briefs/brf_1/items/itm_1"
        )
        XCTAssertEqual(Endpoint.runs(channelID: "chn_1", cursor: nil, limit: 1).path, "/api/v1/channels/chn_1/runs")
        XCTAssertEqual(Endpoint.run(id: "run_1").path, "/api/v1/runs/run_1")
        XCTAssertEqual(Endpoint.askHistory(briefID: "brf_1", cursor: nil, limit: 20).path, "/api/v1/briefs/brf_1/ask")
        // 客户端不构造任何 /admin/api 路径。
        XCTAssertFalse(Endpoint.channels(cursor: nil, limit: 20).path.contains("admin"))
    }

    func testOnlyHealthSkipsAuthorization() {
        XCTAssertFalse(Endpoint.health.requiresAuthorization)
        XCTAssertTrue(Endpoint.channels(cursor: nil, limit: 20).requiresAuthorization)
        XCTAssertTrue(Endpoint.brief(id: "b").requiresAuthorization)
        XCTAssertTrue(Endpoint.cursor(since: nil).requiresAuthorization)
    }

    func testCursorEndpointAlwaysCarriesSince() {
        // 契约：必须总是带 since；无基线时回落到 1970 年全量。
        let items = Endpoint.cursor(since: nil).queryItems
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "since")
        XCTAssertEqual(items.first?.value, PollingBaseline.sinceString(nil))
        XCTAssertEqual(items.first?.value?.hasPrefix("1970-01-01"), true)

        let baseline = Date(timeIntervalSince1970: 1795140110.774)
        let withBaseline = Endpoint.cursor(since: baseline).queryItems
        XCTAssertEqual(withBaseline.first?.value, PollingBaseline.sinceString(baseline))
    }

    func testBaseURLParsingAcceptsInputVariants() {
        XCTAssertEqual(BaseURLDefaults.parse("reachapi.niuma.art")?.absoluteString, "https://reachapi.niuma.art")
        XCTAssertEqual(BaseURLDefaults.parse("https://reachapi.niuma.art")?.absoluteString, "https://reachapi.niuma.art")
        XCTAssertEqual(BaseURLDefaults.parse("  http://localhost:5100  ")?.absoluteString, "http://localhost:5100")
        XCTAssertNil(BaseURLDefaults.parse(""))
        XCTAssertNil(BaseURLDefaults.parse("   "))
        XCTAssertNil(BaseURLDefaults.parse("ftp://example.com"))
    }
}

// MARK: - 轮询基线

final class PollingBaselineTests: XCTestCase {
    func testBaselineAdvancesToNewestCreatedAt() {
        let baseline = Date(timeIntervalSince1970: 1_000)
        let newest = Date(timeIntervalSince1970: 2_000)
        let payload = CursorPayload(
            briefs: [
                CursorBrief(id: "b1", channelID: "c1", title: "t1", createdAt: Date(timeIntervalSince1970: 1_500)),
                CursorBrief(id: "b2", channelID: "c2", title: "t2", createdAt: newest)
            ],
            channels: []
        )

        XCTAssertEqual(PollingBaseline.next(baseline: baseline, payload: payload), newest)
    }

    func testBaselineNeverGoesBackwards() {
        let baseline = Date(timeIntervalSince1970: 5_000)
        let payload = CursorPayload(
            briefs: [CursorBrief(id: "b1", channelID: "c1", title: "t1", createdAt: Date(timeIntervalSince1970: 1_000))],
            channels: []
        )
        // 服务端返回更旧的时间时不倒退基线（避免重复标注已见内容）。
        XCTAssertEqual(PollingBaseline.next(baseline: baseline, payload: payload), baseline)
    }

    func testBaselineKeepsNilWhenNoBriefs() {
        let payload = CursorPayload(briefs: [], channels: [])
        XCTAssertNil(PollingBaseline.next(baseline: nil, payload: payload))
        let existing = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(PollingBaseline.next(baseline: existing, payload: payload), existing)
    }

    func testBaselineInitialisesFromFirstPayload() {
        let newest = Date(timeIntervalSince1970: 777)
        let payload = CursorPayload(
            briefs: [CursorBrief(id: "b1", channelID: "c1", title: "t1", createdAt: newest)],
            channels: []
        )
        XCTAssertEqual(PollingBaseline.next(baseline: nil, payload: payload), newest)
    }

    func testBaselineUsesLatestBriefAtFromFixture() throws {
        // 用真实 /cursor 样本验证：取响应中最大的 created_at，而不是本地时间。
        let data = try Fixture.data("cursor")
        let payload = try JSONDecoder().decode(CursorDTO.self, from: data).toDomain()
        let expected = try XCTUnwrap(payload.briefs.map(\.createdAt).max())
        XCTAssertEqual(PollingBaseline.next(baseline: nil, payload: payload), expected)
        XCTAssertLessThan(expected, Date())
    }
}
