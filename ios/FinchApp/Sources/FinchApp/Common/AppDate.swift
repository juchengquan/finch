import Foundation

/// Shared POSIX date/time formatters. The app stores dates as `yyyy-MM-dd` and
/// times as `HH:mm`; these were re-created inline in ~10 screens. Centralized so
/// every screen formats/parses identically. (Local calendar/timezone, matching
/// the previous per-screen `DateFormatter` instances.)
enum AppDate {
    static let isoDay = make("yyyy-MM-dd")
    static let isoTime = make("HH:mm")
    static let isoDateTime = make("yyyy-MM-dd HH:mm")

    /// The current locale forced to a 24-hour clock — region/date format are
    /// otherwise unchanged. Use to render times as 24h regardless of the device's
    /// 12/24-hour setting: `.locale(AppDate.h24Locale)` on a `Date.FormatStyle`,
    /// or `.environment(\.locale, AppDate.h24Locale)` on a `DatePicker`.
    static let h24Locale: Locale = {
        var c = Locale.Components(locale: .current)
        c.hourCycle = .zeroToTwentyThree
        return Locale(components: c)
    }()

    /// Today as `yyyy-MM-dd`.
    static func today() -> String { isoDay.string(from: Date()) }

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
