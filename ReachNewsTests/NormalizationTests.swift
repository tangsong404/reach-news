import XCTest
@testable import ReachNews

// MARK: - 归一化与枚举

final class NormalizationTests: XCTestCase {
    func testMissedReasonKeepsUnknownValues() {
        XCTAssertEqual(MissedReason.parse("no-material"), .noMaterial)
        XCTAssertEqual(MissedReason.parse("queue-timeout"), .queueTimeout)
        XCTAssertEqual(MissedReason.parse("resume-writing"), .resumeWriting)
        // 服务端会新增原因：未知值必须保留原文。
        XCTAssertEqual(MissedReason.parse("rate-limited"), .unknown("rate-limited"))
        XCTAssertEqual(MissedReason.parse("rate-limited")?.rawValue, "rate-limited")
        XCTAssertNil(MissedReason.parse(nil))
        XCTAssertNil(MissedReason.parse(""))
    }

    func testErrorCodeKeepsUnknownValues() {
        XCTAssertEqual(APIErrorCode.parse("unauthorized"), .unauthorized)
        XCTAssertEqual(APIErrorCode.parse("not_found"), .notFound)
        XCTAssertEqual(APIErrorCode.parse("invalid_input"), .invalidInput)
        XCTAssertEqual(APIErrorCode.parse("busy"), .busy)
        XCTAssertEqual(APIErrorCode.parse("bad_request"), .badRequest)
        XCTAssertEqual(APIErrorCode.parse("internal_error"), .internalError)
        XCTAssertEqual(APIErrorCode.parse("teapot"), .unknown("teapot"))
        XCTAssertEqual(APIErrorCode.parse("teapot").rawValue, "teapot")
    }

    func testErrorEnvelopeNormalization() throws {
        let busy = Data(#"{"error":{"code":"busy","message":"Channel has a run in progress"}}"#.utf8)
        let decoded = try JSONDecoder().decode(ErrorEnvelope.self, from: busy)
        XCTAssertEqual(decoded.normalized, .busy("Channel has a run in progress"))
        XCTAssertTrue(decoded.normalized.isBusy)

        let notFound = Data(#"{"error":{"code":"not_found","message":"Resource not found"}}"#.utf8)
        let decodedNotFound = try JSONDecoder().decode(ErrorEnvelope.self, from: notFound)
        XCTAssertEqual(decodedNotFound.normalized, .notFound)
    }

    func testRunStateThreeWaySplit() {
        XCTAssertTrue(RunState.queued.isRunning)
        XCTAssertTrue(RunState.collecting.isRunning)
        XCTAssertTrue(RunState.writing.isRunning)

        XCTAssertFalse(RunState.published.isRunning)
        XCTAssertTrue(RunState.published.producedBrief)

        // missed 不是失败，也不产出日报。
        XCTAssertFalse(RunState.missed.isRunning)
        XCTAssertFalse(RunState.missed.producedBrief)

        XCTAssertFalse(RunState.failed.isRunning)
        XCTAssertFalse(RunState.cancelled.producedBrief)
        XCTAssertEqual(RunState(rawValue: "collecting"), .collecting)
    }

    func testChannelKindParsing() {
        XCTAssertEqual(ChannelKind(apiValue: "channel"), .channel)
        XCTAssertEqual(ChannelKind(apiValue: "follow"), .follow)
        // 后端 CHANNEL_KINDS 已含 preset。
        XCTAssertEqual(ChannelKind(apiValue: "preset"), .preset)
        // 未知值回落为普通频道，不崩溃、不丢数据。
        XCTAssertEqual(ChannelKind(apiValue: "something-new"), .channel)
        XCTAssertEqual(ChannelKind(apiValue: nil), .channel)
    }

    func testPresetChannelsAreNotUserVisible() {
        // preset 是管理员模板且会参与调度，不能混进用户列表。
        XCTAssertFalse(ChannelKind.preset.isUserVisible)
        XCTAssertTrue(ChannelKind.channel.isUserVisible)
        XCTAssertTrue(ChannelKind.follow.isUserVisible)
    }

    func testSessionExpiry() {
        let expired = AuthSession(
            token: "t",
            expiresAt: Date(timeIntervalSinceNow: -1),
            userName: "a"
        )
        XCTAssertTrue(expired.isExpired())

        let live = AuthSession(
            token: "t",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            userName: "a"
        )
        XCTAssertFalse(live.isExpired())
    }

    func testScheduleParsingAndNormalization() {
        let schedule = Schedule(timesByWeekday: [
            "mon": ["08:00", "8:00", "25:00"],
            "wed": ["08:00"],
            "sat": []
        ])

        // 非两位小时与越界时间被丢弃；重复时刻去重。
        XCTAssertEqual(schedule.times(for: Schedule.Weekday.all[0]), ["08:00"])
        XCTAssertEqual(schedule.times(for: Schedule.Weekday.all[2]), ["08:00"])
        XCTAssertTrue(schedule.times(for: Schedule.Weekday.all[5]).isEmpty)

        XCTAssertEqual(schedule.activeWeekdays.map(\.key), ["mon", "wed"])
        XCTAssertEqual(schedule.allTimes, ["08:00"])
        XCTAssertFalse(schedule.isEmpty)
    }

    func testScheduleToggleAndAddRemove() {
        var schedule = Schedule()
        XCTAssertTrue(schedule.isEmpty)

        let monday = Schedule.Weekday.all[0]
        schedule.toggle(monday, at: "08:00")
        XCTAssertTrue(schedule.isEnabled(monday))
        XCTAssertEqual(schedule.times(for: monday), ["08:00"])

        schedule.addTime("18:00", to: monday)
        XCTAssertEqual(schedule.times(for: monday), ["08:00", "18:00"])

        schedule.removeTime("08:00", from: monday)
        XCTAssertEqual(schedule.times(for: monday), ["18:00"])

        schedule.toggle(monday, at: "18:00")
        XCTAssertFalse(schedule.isEnabled(monday))
        XCTAssertTrue(schedule.isEmpty)
    }

    func testScheduleValidation() {
        XCTAssertTrue(Schedule.isValid("00:00"))
        XCTAssertTrue(Schedule.isValid("23:59"))
        XCTAssertFalse(Schedule.isValid("24:00"))
        XCTAssertFalse(Schedule.isValid("08:60"))
        XCTAssertFalse(Schedule.isValid("8:00"))
        XCTAssertFalse(Schedule.isValid("0800"))
        XCTAssertFalse(Schedule.isValid(""))
    }

    override func setUp() {
        super.setUp()
        // 默认回退 Asia/Shanghai；单个用例改了时区后在这里复位。
        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
    }

    func testDisplayTimeUsesShanghaiTimeZone() {
        // 02:01:50 UTC 在 Asia/Shanghai 是 10:01。
        let date = Date(timeIntervalSince1970: 1795140110.774)
        let locale = Locale(identifier: "zh-Hans")
        XCTAssertEqual(DisplayTime.clock(date, locale: locale), "10:01")
        XCTAssertEqual(DisplayTime.monthDayTime(date, locale: locale), "11月20日 10:01")
        XCTAssertEqual(DisplayTime.monthDay(date, locale: locale), "11月20日")
    }

    func testDayRuleTitleUsesRelativeWordsForTodayAndYesterday() {
        let calendar = Calendar.shanghai
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = calendar.date(byAdding: .day, value: -3, to: now)!
        let locale = Locale(identifier: "zh-Hans")

        XCTAssertEqual(DisplayTime.dayRuleTitle(now, now: now, locale: locale), "今天")
        XCTAssertEqual(DisplayTime.dayRuleTitle(yesterday, now: now, locale: locale), "昨天")
        XCTAssertEqual(DisplayTime.dayRuleTitle(older, now: now, locale: locale), "11月17日")
    }

    func testDayGroupingBucketsByShanghaiDay() {
        let calendar = Calendar.shanghai
        // 同一 UTC 日跨 Shanghai 日界：Shanghai 11-20 01:00 与 11-19 23:30 分属两天。
        let lateUtc = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 1))!
        let early = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 23, minute: 30))!

        let briefs = [
            makeBrief(id: "b1", createdAt: lateUtc),
            makeBrief(id: "b2", createdAt: early)
        ]
        let groups = BriefFeed.groupedByDay(briefs)

        XCTAssertEqual(groups.count, 2)
        // 倒序：Shanghai 11-20 在前。
        XCTAssertEqual(groups.first?.briefs.map(\.id), ["b1"])
        XCTAssertEqual(groups.last?.briefs.map(\.id), ["b2"])
    }

    func testChannelTintIsStablePerID() {
        let id = "chn_c7e81f00-3a2f-4f7b-9a1e-0d5c2b7e4a11"
        let first = ChannelTint.fallbackColor(for: id)
        let second = ChannelTint.fallbackColor(for: id)
        XCTAssertEqual(first, second)
        // 同一 id 永远落在同一索引。
        XCTAssertEqual(Palette.channelTints.firstIndex(of: first),
                       Palette.channelTints.firstIndex(of: second))
    }

    // MARK: 辅助

    private func makeBrief(id: String, createdAt: Date) -> Brief {
        Brief(
            id: id,
            channelID: "chn_test",
            title: id,
            sections: [],
            memorySummary: "",
            createdAt: createdAt
        )
    }
}

// MARK: - 服务端时区（A45 / A46）

final class ServiceTimeZoneTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
    }

    override func tearDown() {
        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
        super.tearDown()
    }

    func testResolveAcceptsValidIdentifier() {
        XCTAssertEqual(ServiceTimeZone.resolve("Asia/Tokyo").identifier, "Asia/Tokyo")
        XCTAssertEqual(ServiceTimeZone.resolve("UTC").identifier, "GMT")
    }

    func testResolveFallsBackOnMissingOrInvalid() {
        // 缺失或非法都回退 Asia/Shanghai，与调度器一致。
        XCTAssertEqual(ServiceTimeZone.resolve(nil).identifier, "Asia/Shanghai")
        XCTAssertEqual(ServiceTimeZone.resolve("").identifier, "Asia/Shanghai")
        XCTAssertEqual(ServiceTimeZone.resolve("   ").identifier, "Asia/Shanghai")
        XCTAssertEqual(ServiceTimeZone.resolve("Not/AZone").identifier, "Asia/Shanghai")
    }

    func testDisplayIdentifierKeepsRawOrFallsBack() {
        XCTAssertEqual(ServiceTimeZone.displayIdentifier("Asia/Tokyo"), "Asia/Tokyo")
        XCTAssertEqual(ServiceTimeZone.displayIdentifier(nil), "Asia/Shanghai")
        XCTAssertEqual(ServiceTimeZone.displayIdentifier("Bogus/Zone"), "Asia/Shanghai")
    }

    func testDisplayTimeFollowsActiveTimeZone() {
        let date = Date(timeIntervalSince1970: 1795140110.774)  // 2026-11-20T02:01:50.774Z
        let locale = Locale(identifier: "zh-Hans")

        DisplayTime.setTimeZone(ServiceTimeZone.resolve("Asia/Shanghai"))
        XCTAssertEqual(DisplayTime.clock(date, locale: locale), "10:01")

        // 换成东京后同一时刻应显示 +1 小时。
        DisplayTime.setTimeZone(ServiceTimeZone.resolve("Asia/Tokyo"))
        XCTAssertEqual(DisplayTime.clock(date, locale: locale), "11:01")
        XCTAssertEqual(DisplayTime.timeZoneIdentifier, "Asia/Tokyo")
    }

    func testDayGroupingFollowsActiveTimeZone() {
        let utc = Date(timeIntervalSince1970: 1795140110.774)  // 02:01Z
        let locale = Locale(identifier: "zh-Hans")
        let now = utc

        DisplayTime.setTimeZone(ServiceTimeZone.resolve("Asia/Shanghai"))
        XCTAssertEqual(DisplayTime.dayRuleTitle(utc, now: now, locale: locale), "今天")

        // 同一时刻在纽约仍在同一天，但日期可能不同；只验证不崩溃且一致。
        DisplayTime.setTimeZone(ServiceTimeZone.resolve("America/New_York"))
        let title = DisplayTime.dayRuleTitle(utc, now: now, locale: locale)
        XCTAssertFalse(title.isEmpty)
    }

    func testServiceCalendarMatchesActiveTimeZone() {
        DisplayTime.setTimeZone(ServiceTimeZone.resolve("Asia/Tokyo"))
        XCTAssertEqual(Calendar.shanghai.timeZone.identifier, "Asia/Tokyo")

        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
        XCTAssertEqual(Calendar.shanghai.timeZone.identifier, "Asia/Shanghai")
    }
}

// MARK: - 服务端时区接口

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testLoadAppliesServerTimeZone() async {
        let transport = StubTransport(json: #"{"timeZone":"Asia/Tokyo"}"#)
        let client = TestClient.make(transport: transport)
        let store = SettingsStore(client: client)

        await store.load()

        XCTAssertEqual(store.displayTimeZone, "Asia/Tokyo")
        XCTAssertEqual(DisplayTime.timeZone.identifier, "Asia/Tokyo")
        XCTAssertTrue(store.isLoaded)
        XCTAssertEqual(transport.recorded.first?.url.path, "/api/v1/settings")
        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
    }

    @MainActor
    func testLoadFallsBackWhenFieldMissing() async {
        let transport = StubTransport(json: #"{}"#)
        let store = SettingsStore(client: TestClient.make(transport: transport))
        DisplayTime.setTimeZone(ServiceTimeZone.resolve("Asia/Tokyo"))

        await store.load()

        XCTAssertEqual(store.displayTimeZone, "Asia/Shanghai")
        XCTAssertEqual(DisplayTime.timeZone.identifier, "Asia/Shanghai")
        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
    }

    @MainActor
    func testLoadFallsBackWhenRequestFails() async {
        let transport = StubTransport(json: #"{"error":{"code":"internal_error","message":"boom"}}"#, status: 500)
        let store = SettingsStore(client: TestClient.make(transport: transport))

        await store.load()

        // 接口失败不阻断主流程：回退默认并记录错误。
        XCTAssertEqual(store.displayTimeZone, "Asia/Shanghai")
        XCTAssertTrue(store.isFallback)
        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
    }

    @MainActor
    func testLoadFallsBackOnInvalidZone() async {
        let transport = StubTransport(json: #"{"timeZone":"Not/AZone"}"#)
        let store = SettingsStore(client: TestClient.make(transport: transport))

        await store.load()

        XCTAssertEqual(store.displayTimeZone, "Asia/Shanghai")
        DisplayTime.setTimeZone(ServiceTimeZone.resolve(nil))
    }
}

// MARK: - 每星期时刻上限

final class ScheduleCapTests: XCTestCase {
    func testAddStopsAtFiveTimesPerWeekday() {
        var schedule = Schedule()
        let monday = Schedule.Weekday.all[0]

        for hour in 6...10 {
            schedule.addTime(String(format: "%02d:00", hour), to: monday)
        }
        XCTAssertEqual(schedule.times(for: monday).count, 5)
        XCTAssertFalse(schedule.canAddTime(to: monday))

        // 第 6 个应被拒绝，不改变已有时刻。
        schedule.addTime("23:00", to: monday)
        XCTAssertEqual(schedule.times(for: monday).count, 5)
        XCTAssertFalse(schedule.times(for: monday).contains("23:00"))
    }

    func testDuplicateTimeDoesNotCountTowardCap() {
        var schedule = Schedule()
        let monday = Schedule.Weekday.all[0]

        schedule.addTime("08:00", to: monday)
        schedule.addTime("08:00", to: monday)

        XCTAssertEqual(schedule.times(for: monday), ["08:00"])
        XCTAssertTrue(schedule.canAddTime(to: monday))
    }

    func testCapIsPerWeekday() {
        var schedule = Schedule()
        let monday = Schedule.Weekday.all[0]
        let tuesday = Schedule.Weekday.all[1]

        for hour in 6...10 { schedule.addTime(String(format: "%02d:00", hour), to: monday) }

        XCTAssertFalse(schedule.canAddTime(to: monday))
        // 其它星期不受影响。
        XCTAssertTrue(schedule.canAddTime(to: tuesday))
        schedule.addTime("09:00", to: tuesday)
        XCTAssertEqual(schedule.times(for: tuesday), ["09:00"])
    }
}

// MARK: - 闹钟式时间选择

final class AlarmScheduleTests: XCTestCase {
    func testSetTimeAppliesToSelectedWeekdaysOnly() {
        var schedule = Schedule()
        let monday = Schedule.Weekday.all[0]
        let tuesday = Schedule.Weekday.all[1]
        let friday = Schedule.Weekday.all[4]

        schedule.setTime("08:30", for: [monday, friday])

        XCTAssertEqual(schedule.times(for: monday), ["08:30"])
        XCTAssertEqual(schedule.times(for: friday), ["08:30"])
        XCTAssertTrue(schedule.times(for: tuesday).isEmpty)
    }

    func testWeekdaysAtTimeReturnsMatchingSelection() {
        var schedule = Schedule()
        schedule.setTime("09:00", for: [Schedule.Weekday.all[0], Schedule.Weekday.all[2]])
        schedule.setTime("18:00", for: [Schedule.Weekday.all[1]])

        XCTAssertEqual(schedule.weekdays(at: "09:00").map(\.key), ["mon", "wed"])
        XCTAssertEqual(schedule.weekdays(at: "18:00").map(\.key), ["tue"])
        XCTAssertEqual(schedule.weekdays(at: "23:00"), [])
    }

    func testChangingTimeUpdatesAllSelectedWeekdays() {
        // 闹钟语义：改时间，已选星期一起变。
        var schedule = Schedule()
        let monday = Schedule.Weekday.all[0]
        let wednesday = Schedule.Weekday.all[2]
        schedule.setTime("08:00", for: [monday, wednesday])

        schedule.setTime("07:15", for: schedule.weekdays(at: "08:00"))

        XCTAssertEqual(schedule.times(for: monday), ["07:15"])
        XCTAssertEqual(schedule.times(for: wednesday), ["07:15"])
        XCTAssertTrue(schedule.weekdays(at: "08:00").isEmpty)
    }

    func testInvalidTimeIsRejected() {
        var schedule = Schedule()
        let monday = Schedule.Weekday.all[0]

        schedule.setTime("25:99", for: [monday])

        XCTAssertTrue(schedule.times(for: monday).isEmpty)
    }

    func testToggleWithTimeEnablesAndDisables() {
        var schedule = Schedule()
        let saturday = Schedule.Weekday.all[5]

        schedule.toggle(saturday, at: "01:25")
        XCTAssertEqual(schedule.times(for: saturday), ["01:25"])

        schedule.toggle(saturday, at: "01:25")
        XCTAssertTrue(schedule.times(for: saturday).isEmpty)
    }
}

// MARK: - 频道颜色（仅本机）

final class ChannelColorTests: XCTestCase {
    func testFallbackIsStablePerChannel() {
        let id = "chn_abc"
        XCTAssertEqual(ChannelTint.fallbackIndex(for: id), ChannelTint.fallbackIndex(for: id))
        XCTAssertTrue((0..<ChannelTint.count).contains(ChannelTint.fallbackIndex(for: id)))
    }

    func testLeastUsedIndexPicksUnusedColor() {
        // 0 与 1 已用，应返回下一个未使用的 2，而不是重色。
        XCTAssertEqual(ChannelTint.leastUsedIndex(among: [0, 1]), 2)
        // 全空时返回 0。
        XCTAssertEqual(ChannelTint.leastUsedIndex(among: []), 0)
        // 0 用了两次、1/2/3 各一次：仍优先挑完全没用过的颜色（4）。
        XCTAssertEqual(ChannelTint.leastUsedIndex(among: [0, 0, 1, 2, 3]), 4)
        // 调色板全部用满后，才回落到用得最少的那个。
        let allUsed = Array(0..<ChannelTint.count) + [0, 0]
        let picked = ChannelTint.leastUsedIndex(among: allUsed)
        XCTAssertTrue((0..<ChannelTint.count).contains(picked))
        XCTAssertNotEqual(picked, 0)
    }

    func testPaletteHasEnoughDistinctColors() {
        // 曾经只有 4 色导致频道重复撞色。
        XCTAssertGreaterThanOrEqual(ChannelTint.count, 8)
        XCTAssertEqual(Set((0..<ChannelTint.count).map { ChannelTint.color(at: $0).description }).count,
                       ChannelTint.count)
    }

    @MainActor
    func testStorePersistsAndForgets() {
        let storage = InMemoryChannelColors()
        let store = ChannelColorStore(storage: storage)

        store.setColorIndex(2, for: "chn_1")
        XCTAssertEqual(store.colorIndex(for: "chn_1"), 2)
        XCTAssertEqual(store.effectiveIndex(for: "chn_1"), 2)

        store.forget("chn_1")
        XCTAssertNil(store.colorIndex(for: "chn_1"))
        // 清除后回退到按 id 的稳定色。
        XCTAssertEqual(store.effectiveIndex(for: "chn_1"), ChannelTint.fallbackIndex(for: "chn_1"))
    }

    @MainActor
    func testSuggestedIndexAvoidsUsedColors() {
        let storage = InMemoryChannelColors()
        let store = ChannelColorStore(storage: storage)
        store.setColorIndex(0, for: "a")
        store.setColorIndex(1, for: "b")

        XCTAssertEqual(store.suggestedIndex(), 2)
    }
}
