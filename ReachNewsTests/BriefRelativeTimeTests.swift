import XCTest
@testable import ReachNews

final class BriefRelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let zh = Locale(identifier: "zh-Hans")

    func testElapsedBoundariesAndFuture() {
        let cases: [(TimeInterval, String)] = [(-10, "刚刚"), (0, "刚刚"), (59, "刚刚"),
            (60, "1分钟前"), (3599, "59分钟前"), (3600, "1小时前"), (86399, "23小时前")]
        for (elapsed, expected) in cases {
            XCTAssertEqual(BriefRelativeTime.string(for: now.addingTimeInterval(-elapsed), now: now, locale: zh), expected)
        }
    }

    func testDateAfter24HoursAndCrossYear() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let iso = ISO8601DateFormatter()
        let current = iso.date(from: "2027-01-02T12:00:00Z")!
        let sameYear = iso.date(from: "2027-01-01T12:00:00Z")!
        let previousYear = iso.date(from: "2026-12-31T12:00:00Z")!
        let day = BriefRelativeTime.string(for: sameYear, now: current, locale: zh, timeZone: zone)
        XCTAssertFalse(day.contains("小时前"))
        XCTAssertFalse(day.contains("2027"))
        XCTAssertTrue(BriefRelativeTime.string(for: previousYear, now: current, locale: zh, timeZone: zone).contains("2026"))
    }

    func testEnglishStrings() {
        let en = Locale(identifier: "en")
        XCTAssertEqual(BriefRelativeTime.string(for: now, now: now, locale: en), "Just now")
        XCTAssertEqual(BriefRelativeTime.string(for: now.addingTimeInterval(-120), now: now, locale: en), "2 min ago")
    }
}
