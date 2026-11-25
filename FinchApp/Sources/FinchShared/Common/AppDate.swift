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

    /// The app's short style for SHOWING a `yyyy-MM-dd` day: "Nov 15", or "Nov 15, 2025"
    /// outside `today`'s year ("11月15日" / "2025年11月15日" in Chinese). Display only —
    /// what is stored, compared or passed to the engine stays ISO. A string that isn't
    /// a day (a "—" placeholder) comes back as is.
    ///
    /// Always Gregorian, like the stored days: a region set to the Buddhist or Japanese
    /// calendar would otherwise print 2568 or Reiwa 7 for a year compared as 2025.
    static func shortDay(_ iso: String, today: String, locale: Locale = .autoupdatingCurrent) -> String {
        shortDay(iso, withYear: iso.prefix(4) != today.prefix(4), locale: locale)
    }

    static func shortDay(_ iso: String, withYear: Bool, locale: Locale = .autoupdatingCurrent) -> String {
        guard let d = isoDay.date(from: iso) else { return iso }
        let cal = civil
        let style = Date.FormatStyle(locale: locale, calendar: cal, timeZone: cal.timeZone)
            .month(.abbreviated).day()
        return d.formatted(withYear ? style.year() : style)
    }

    /// A day with its weekday, for the calendar's selected-day headline: "Wed, Jul 15"
    /// in English, "7月15日周三" in Chinese. It was a fixed "EEE, MMM d", which kept
    /// English order and punctuation in every language ("周三, 7月 15").
    static func weekdayDay(_ iso: String, locale: Locale = .autoupdatingCurrent) -> String {
        guard let d = isoDay.date(from: iso) else { return iso }
        return d.formatted(style(locale).weekday(.abbreviated).month(.abbreviated).day())
    }

    /// A month and its year: "July 2026" / "2026年7月" (`wide`), "Jul 2026" / "2026年7月".
    /// Takes `yyyy-MM` (or any `yyyy-MM…` day); anything else comes back as is.
    static func monthYear(_ ym: String, wide: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        guard ym.count >= 7, let d = isoDay.date(from: "\(ym.prefix(7))-01") else { return ym }
        return monthYear(d, wide: wide, locale: locale)
    }
    static func monthYear(_ date: Date, wide: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(style(locale).month(wide ? .wide : .abbreviated).year())
    }

    /// A month on its own, 1–12: "Jul" / "7月".
    static func monthName(_ month: Int, locale: Locale = .autoupdatingCurrent) -> String {
        guard (1...12).contains(month),
              let d = civil.date(from: DateComponents(year: 2001, month: month, day: 1)) else { return "\(month)" }
        return d.formatted(style(locale).month(.abbreviated))
    }

    /// The engine labels its monthly chart points "Jan"…"Dec" (`MonthlyPoint.m`, kept
    /// in step with the web's). This is that label in the reader's language.
    static func chartMonth(_ engineLabel: String, locale: Locale = .autoupdatingCurrent) -> String {
        let english = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard let i = english.firstIndex(of: engineLabel) else { return engineLabel }
        return monthName(i + 1, locale: locale)
    }

    /// A budget cycle's start on the history chart's x axis. The labels must be
    /// unique across the ~6 bars (Swift Charts stacks equal categorical labels into
    /// one band): a monthly budget's six months never repeat, so the month alone;
    /// quarterly and yearly ones span years, so month and year; day-grained ones,
    /// month and day ("7/15").
    static func budgetCycleLabel(_ from: String, frequency: String, locale: Locale = .autoupdatingCurrent) -> String {
        guard let d = isoDay.date(from: from) else { return from }
        switch frequency {
        case "daily", "weekly", "biweekly": return d.formatted(style(locale).month(.defaultDigits).day())
        case "quarterly", "yearly": return monthYear(d, locale: locale)
        default: return d.formatted(style(locale).month(.abbreviated))
        }
    }

    /// Always Gregorian, in the device's zone, like the stored days — see `shortDay`.
    private static func style(_ locale: Locale) -> Date.FormatStyle {
        let cal = civil
        return Date.FormatStyle(locale: locale, calendar: cal, timeZone: cal.timeZone)
    }

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
