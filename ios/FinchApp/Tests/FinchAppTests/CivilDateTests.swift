import XCTest
@testable import FinchApp

/// `yyyy-MM-dd` values in this app are **civil dates** (a day on the user's
/// calendar), not instants. Every conversion between a `Date` and one of these
/// strings must therefore use the *same* timezone on both ends, and that timezone
/// must be the device's — otherwise the day a user sees shifts.
///
/// These are regression tests for a real bug: the app had two `yyyy-MM-dd`
/// converters, `AppDate.isoDay` (no `timeZone`, so local) and a second one inside
/// `FinchStore+ViewHelpers` pinned to **UTC**. They disagreed by up to a day, which
/// put `wallToday` a day behind between 00:00 and 08:00 at UTC+8 and rendered the
/// Scheduled calendar's day header one day early.
///
/// Every assertion below is computed relative to the current timezone, so these
/// pass in any zone — but they fail for any zone offset from UTC if a UTC-pinned
/// converter comes back.
@MainActor   // FinchStore is @MainActor, so its static day helpers are isolated too.
final class CivilDateTests: XCTestCase {

    /// Build the instant for a given local wall-clock time.
    private func localInstant(_ y: Int, _ m: Int, _ d: Int, _ hour: Int) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (y, m, d, hour, 30)
        return AppDate.civil.date(from: c)!
    }

    // MARK: the two converters must agree

    func test_storeIsoDay_matchesAppDateIsoDay() {
        // The bug was these two disagreeing. Sweep a full day of local wall-clock
        // hours so any fixed offset is caught, not just the one the test ran at.
        for hour in 0..<24 {
            let instant = localInstant(2026, 7, 15, hour)
            XCTAssertEqual(FinchStore.isoDay(instant),
                           AppDate.isoDay.string(from: instant),
                           "converters disagree at local hour \(hour)")
        }
    }

    /// The specific window that was broken: just after local midnight, a UTC-pinned
    /// formatter still reports the previous day for any zone ahead of UTC.
    func test_isoDay_justAfterLocalMidnight_isThatLocalDay() {
        XCTAssertEqual(FinchStore.isoDay(localInstant(2026, 7, 15, 0)), "2026-07-15")
        XCTAssertEqual(FinchStore.isoDay(localInstant(2026, 7, 15, 23)), "2026-07-15")
    }

    // MARK: parse/format round-trips

    func test_isoDay_roundTrips() {
        for iso in ["2026-01-01", "2026-07-15", "2026-12-31"] {
            let parsed = AppDate.isoDay.date(from: iso)
            XCTAssertNotNil(parsed, "failed to parse \(iso)")
            XCTAssertEqual(AppDate.isoDay.string(from: parsed!), iso)
        }
    }

    /// The mixing bug in one assertion: parse with `AppDate`, then read components
    /// back through `AppDate.civil`. With a hardcoded-UTC calendar this returned
    /// Jul 14 at UTC+8 — which is exactly what the day header displayed.
    func test_civilCalendar_componentsMatchTheParsedString() {
        let d = AppDate.isoDay.date(from: "2026-07-15")!
        let c = AppDate.civil.dateComponents([.year, .month, .day], from: d)
        XCTAssertEqual([c.year, c.month, c.day], [2026, 7, 15])
    }

    func test_civilCalendar_usesTheDeviceTimeZone() {
        XCTAssertEqual(AppDate.civil.timeZone, TimeZone.current)
    }

    /// Day arithmetic must land on the civil day the string names — the Scheduled
    /// calendar's 90-day "Upcoming" bound is computed this way.
    func test_civilCalendar_dayArithmeticStaysOnCivilDays() {
        let start = AppDate.isoDay.date(from: "2026-07-15")!
        let plus90 = AppDate.civil.date(byAdding: .day, value: 90, to: start)!
        XCTAssertEqual(AppDate.isoDay.string(from: plus90), "2026-10-13")
    }

    /// Crossing a DST boundary must still advance exactly one civil day. (In zones
    /// without DST — e.g. UTC+8 — this is trivially true; it guards travellers.)
    func test_civilCalendar_dayArithmeticSurvivesDstBoundaries() {
        for iso in ["2026-03-08", "2026-11-01"] {   // US DST transitions
            let start = AppDate.isoDay.date(from: iso)!
            let next = AppDate.civil.date(byAdding: .day, value: 1, to: start)!
            let c = AppDate.civil.dateComponents([.day], from: next)
            let expected = AppDate.civil.dateComponents([.day], from: start).day! + 1
            XCTAssertEqual(c.day, expected, "one day after \(iso) was not the next civil day")
        }
    }
}
