import Foundation

/// Shared POSIX date/time formatters. The app stores dates as `yyyy-MM-dd` and
/// times as `HH:mm`; these were re-created inline in ~10 screens. Centralized so
/// every screen formats/parses identically. (Local calendar/timezone, matching
/// the previous per-screen `DateFormatter` instances.)
enum AppDate {
    static let isoDay = make("yyyy-MM-dd")
    static let isoTime = make("HH:mm")
    static let isoDateTime = make("yyyy-MM-dd HH:mm")

    /// Today as `yyyy-MM-dd`.
    static func today() -> String { isoDay.string(from: Date()) }

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
