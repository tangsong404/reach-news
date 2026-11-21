import Foundation

// MARK: - 时区来源
//
// 服务端通过 GET /api/v1/settings 返回 { timeZone }，客户端所有时刻展示与
// 日期分组都按它解释。配置缺失或非法时回退 Asia/Shanghai，与调度器一致。

enum ServiceTimeZone {
    static let fallbackIdentifier = "Asia/Shanghai"

    /// 校验并归一化服务端返回的 IANA 时区名。
    static func resolve(_ raw: String?) -> TimeZone {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let zone = TimeZone(identifier: raw) else {
            return TimeZone(identifier: fallbackIdentifier)
                ?? TimeZone(secondsFromGMT: 8 * 3600)!
        }
        return zone
    }

    /// 展示用的短名，取服务端返回的原始标识（如 Asia/Tokyo）。
    static func displayIdentifier(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              TimeZone(identifier: raw) != nil else {
            return fallbackIdentifier
        }
        return raw
    }
}

// MARK: - 时间展示
//
// 服务端一律 UTC ISO 8601；展示按服务端配置的时区。不存储格式化字符串。
//
// 时区是运行时值而不是常量：服务端配置变化后界面应随之变化。

enum DisplayTime {
    /// 当前生效的时区。由 SettingsStore 注入，默认回退 Asia/Shanghai。
    nonisolated(unsafe) private static var activeTimeZone: TimeZone = ServiceTimeZone.resolve(nil)

    static var timeZone: TimeZone { activeTimeZone }

    static func setTimeZone(_ zone: TimeZone) {
        activeTimeZone = zone
    }

    static var timeZoneIdentifier: String {
        activeTimeZone.identifier
    }

    private static func formatter(_ format: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = activeTimeZone
        formatter.dateFormat = format
        return formatter
    }

    /// 「08:00」
    static func clock(_ date: Date, locale: Locale) -> String {
        formatter("HH:mm", locale: locale).string(from: date)
    }

    /// 「11月20日 08:00」
    static func monthDayTime(_ date: Date, locale: Locale) -> String {
        formatter("M月d日 HH:mm", locale: locale).string(from: date)
    }

    /// 「11月20日」
    static func monthDay(_ date: Date, locale: Locale) -> String {
        formatter("M月d日", locale: locale).string(from: date)
    }

    /// 「2026年11月20日」
    static func longDate(_ date: Date, locale: Locale) -> String {
        formatter("yyyy年M月d日", locale: locale).string(from: date)
    }

    /// 「11月20日 星期四」
    static func monthDayWeekday(_ date: Date, locale: Locale) -> String {
        formatter("M月d日 EEEE", locale: locale).string(from: date)
    }

    /// 日期分组的标题：今天、昨天，更早用日期。
    static func dayRuleTitle(_ date: Date, now: Date, locale: Locale, calendar: Calendar? = nil) -> String {
        let calendar = calendar ?? serviceCalendar
        if calendar.isDate(date, inSameDayAs: now) {
            return L10n.string("feed.day.today", locale: locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return L10n.string("feed.day.yesterday", locale: locale)
        }
        return monthDay(date, locale: locale)
    }

    /// 与当前生效时区一致的日历，用于日期分组与时间表解析。
    static var serviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = activeTimeZone
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        return calendar
    }
}

extension Calendar {
    /// 按服务端时区解释日期与时刻。
    static var shanghai: Calendar {
        DisplayTime.serviceCalendar
    }
}
