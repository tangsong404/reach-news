import XCTest
@testable import ReachNews

// MARK: - 日报流逻辑（筛选、去重、搜索）

final class FilterTests: XCTestCase {
    private let calendar = Calendar.shanghai

    func testMergeDeduplicatesByID() {
        let existing = [makeBrief(id: "a", createdAt: day(20)), makeBrief(id: "b", createdAt: day(19))]
        let incoming = [makeBrief(id: "b", createdAt: day(19)), makeBrief(id: "c", createdAt: day(18))]

        let merged = BriefFeed.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
    }

    func testMergeKeepsDescendingOrder() {
        let existing = [makeBrief(id: "a", createdAt: day(18))]
        let incoming = [makeBrief(id: "b", createdAt: day(20)), makeBrief(id: "c", createdAt: day(19))]

        let merged = BriefFeed.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.map(\.id), ["b", "c", "a"])
    }

    func testMergeWithEmptyIncomingKeepsExisting() {
        let existing = [makeBrief(id: "a", createdAt: day(20))]
        XCTAssertEqual(BriefFeed.merge(existing: existing, incoming: []).map(\.id), ["a"])
        XCTAssertTrue(BriefFeed.merge(existing: [], incoming: []).isEmpty)
    }

    func testSearchFiltersByTitleOnly() {
        let briefs = [
            makeBrief(id: "a", title: "模型竞赛进入下半场", createdAt: day(20)),
            makeBrief(id: "b", title: "算力租赁价格回落", createdAt: day(19))
        ]

        XCTAssertEqual(BriefFeed.search(briefs, query: "模型").map(\.id), ["a"])
        XCTAssertEqual(BriefFeed.search(briefs, query: "价格").map(\.id), ["b"])
        XCTAssertEqual(BriefFeed.search(briefs, query: "  ").count, 2)
        XCTAssertTrue(BriefFeed.search(briefs, query: "不存在的词").isEmpty)
        // 大小写不敏感。
        XCTAssertEqual(BriefFeed.search(briefs, query: "模型").count, 1)
    }

    func testFilterByChannel() {
        var filter = FeedFilter()
        filter.channelIDs = ["chn_1"]

        let briefs = [
            makeBrief(id: "a", channelID: "chn_1", createdAt: day(20)),
            makeBrief(id: "b", channelID: "chn_2", createdAt: day(19))
        ]
        XCTAssertEqual(BriefFeed.filtered(briefs, query: "", filter: filter).map(\.id), ["a"])
    }

    func testFilterByMultipleChannels() {
        var filter = FeedFilter()
        filter.channelIDs = ["chn_1", "chn_2"]

        let briefs = [
            makeBrief(id: "a", channelID: "chn_1", createdAt: day(20)),
            makeBrief(id: "b", channelID: "chn_2", createdAt: day(19)),
            makeBrief(id: "c", channelID: "chn_3", createdAt: day(18))
        ]
        XCTAssertEqual(BriefFeed.filtered(briefs, query: "", filter: filter).map(\.id), ["a", "b"])
    }

    func testThisWeekFilterExcludesOlderBriefs() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        var filter = FeedFilter()
        filter.time = .thisWeek

        let range = try? XCTUnwrap(filter.resolvedRange(now: now))
        XCTAssertNotNil(range)

        let inside = makeBrief(id: "in", createdAt: now)
        let outside = makeBrief(
            id: "out",
            createdAt: calendar.date(byAdding: .day, value: -30, to: now)!
        )

        let result = BriefFeed.filtered([inside, outside], query: "", filter: filter)
        XCTAssertEqual(result.map(\.id), ["in"])
    }

    func testCustomRangeRequiresBothEnds() {
        var filter = FeedFilter()
        filter.time = .custom

        // 缺任一端时不构成区间，也就不会误筛掉内容。
        XCTAssertNil(filter.resolvedRange(now: Date()))
        XCTAssertNil(filter.dateRange)

        filter.startDate = day(10)
        filter.endDate = day(20)
        let range = filter.resolvedRange(now: Date())
        XCTAssertNotNil(range)
    }

    func testCustomRangeSwapsReversedDates() {
        var filter = FeedFilter()
        filter.time = .custom
        filter.startDate = day(20)
        filter.endDate = day(10)

        let range = try? XCTUnwrap(filter.resolvedRange(now: Date()))
        // 范围按整天解释：起点是当天零点，终点覆盖到当天结束。
        XCTAssertEqual(range?.lowerBound, calendar.startOfDay(for: day(10)))
        let expectedUpper = calendar.startOfDay(for: day(20)).addingTimeInterval(24 * 3600 - 0.001)
        XCTAssertEqual(range?.upperBound.timeIntervalSince1970 ?? 0, expectedUpper.timeIntervalSince1970, accuracy: 0.002)
    }

    func testActiveDimensionCount() {
        var filter = FeedFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.activeDimensionCount, 0)

        filter.time = .thisMonth
        XCTAssertEqual(filter.activeDimensionCount, 1)

        filter.channelIDs = ["chn_1", "chn_2"]
        // 时间一个维度、频道多选一个维度。
        XCTAssertEqual(filter.activeDimensionCount, 2)
        XCTAssertTrue(filter.isActive)
    }

    func testRequiredLowerBoundDrivesLoading() {
        var filter = FeedFilter()
        filter.time = .custom
        filter.startDate = day(10)
        filter.endDate = day(20)

        XCTAssertEqual(filter.requiredLowerBound, calendar.startOfDay(for: day(10)))
        XCTAssertEqual(filter.requiredLowerBound, calendar.startOfDay(for: day(10)))

        filter.time = .all
        XCTAssertNil(filter.requiredLowerBound)
    }

    func testCoversLowerBoundDetectsLoadedRange() {
        let bound = day(10)
        let briefs = [makeBrief(id: "a", createdAt: day(20)), makeBrief(id: "b", createdAt: day(5))]
        XCTAssertTrue(BriefFeed.coversLowerBound(briefs, bound: bound))

        let partial = [makeBrief(id: "a", createdAt: day(20)), makeBrief(id: "b", createdAt: day(15))]
        XCTAssertFalse(BriefFeed.coversLowerBound(partial, bound: bound))

        // 没有下界要求时总视为已覆盖。
        XCTAssertTrue(BriefFeed.coversLowerBound(partial, bound: nil))
        XCTAssertTrue(BriefFeed.coversLowerBound([], bound: bound))
    }

    func testGroupingProducesDescendingDays() {
        let briefs = [
            makeBrief(id: "a", createdAt: day(20)),
            makeBrief(id: "b", createdAt: day(19)),
            makeBrief(id: "c", createdAt: day(20))
        ]
        let groups = BriefFeed.groupedByDay(briefs)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].briefs.map(\.id), ["a", "c"])
        XCTAssertEqual(groups[1].briefs.map(\.id), ["b"])
    }

    func testSurveyEntryAndMaterialCountsAreDistinct() {
        // 条目数与素材数不是同一个数：多分组、一条条目引用多个素材。
        let section = BriefSection(
            title: "重点",
            entries: [
                Entry(title: "e1", summary: "", materialIDs: ["m1", "m2", "m3"]),
                Entry(title: "e2", summary: "", materialIDs: ["m1"])
            ]
        )
        let brief = Brief(
            id: "b",
            channelID: "c",
            title: "t",
            sections: [section],
            memorySummary: "",
            createdAt: day(20)
        )

        XCTAssertEqual(brief.entryCount, 2)
        XCTAssertEqual(brief.materialCount, 3)
        XCTAssertEqual(brief.allMaterialIDs, ["m1", "m2", "m3"])
    }

    // MARK: 辅助

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 8))!
    }

    private func makeBrief(
        id: String,
        channelID: String = "chn_1",
        title: String? = nil,
        createdAt: Date
    ) -> Brief {
        Brief(
            id: id,
            channelID: channelID,
            title: title ?? id,
            sections: [],
            memorySummary: "",
            createdAt: createdAt
        )
    }
}
