import Foundation

/// Deterministic elapsed-time formatting; caller supplies now for tests and refresh.
enum BriefRelativeTime {
    static func string(for date: Date, now: Date, locale: Locale,
                       timeZone: TimeZone = DisplayTime.timeZone) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return L10n.string("feed.time.justNow", locale: locale) }
        if elapsed < 3600 {
            return L10n.format("feed.time.minutesAgo", locale: locale, Int(elapsed / 60))
        }
        if elapsed < 86400 {
            return L10n.format("feed.time.hoursAgo", locale: locale, Int(elapsed / 3600))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yyyyMMMd")
        return formatter.string(from: date)
    }
}
