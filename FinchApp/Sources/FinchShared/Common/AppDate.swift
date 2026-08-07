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
    /// Make 24-hour time the app's **ambient** locale, so nothing has to ask for it
    /// per-view. Call once, before any UI is built.
    ///
    /// This exists because of how `UIDatePicker` behaves. The obvious way to get a
    /// 24-hour picker is `.environment(\.locale, h24Locale)`, but a `UIDatePicker`
    /// whose locale *differs from the device's* re-measures its label a beat after
    /// its first layout — and inside a sheet presentation UIKit animates that
    /// correction, so the Date row visibly slid ~23pt left as the sheet opened
    /// (measured: 69px of travel with the override, 1px without). That was fixed once
    /// by replacing the control with our own pills, which cost the system picker's
    /// pop-out calendar; this gets both. With the ambient locale already 24-hour there
    /// is no mismatch, so the plain system picker is 24-hour AND does not reflow.
    ///
    /// `AppleICUForce24HourTime` is undocumented but is an ordinary preference in our
    /// own domain, not a private API. If Apple ever stops honouring it the only
    /// consequence is that the *pickers* follow the device's 12/24-hour setting —
    /// nothing crashes, and text elsewhere still formats through ``h24Locale``, which
    /// is why those call sites deliberately keep it rather than relying on this.
    static func force24HourClock() {
        UserDefaults.standard.set(true, forKey: "AppleICUForce24HourTime")
    }

    static let h24Locale: Locale = {
        var c = Locale.Components(locale: .current)
        c.hourCycle = .zeroToTwentyThree
        return Locale(components: c)
    }()

    /// Today as `yyyy-MM-dd`.
    static func today() -> String { isoDay.string(from: Date()) }

    /// The calendar for civil-date math on `yyyy-MM-dd` strings — Gregorian in the
    /// **device's** timezone, matching the formatters above (which set no `timeZone`
    /// and so parse/format locally).
    ///
    /// Use this instead of hand-rolling a `Calendar`. Parsing an ISO day with
    /// `isoDay` and then doing component math in a **hardcoded-UTC** calendar shifts
    /// the result by a day for every user offset from UTC: at UTC+8, `"2026-07-15"`
    /// parses to local midnight = `2026-07-14T16:00Z`, so UTC components read Jul 14.
    /// That was a real bug — the Scheduled calendar's day header rendered one day
    /// early, and `wallToday` was a day behind between 00:00 and 08:00 local.
    ///
    /// Computed, not `static let`: a cached calendar would pin the timezone at first
    /// access and go stale if the device's changes (travel, DST).
    static var civil: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
