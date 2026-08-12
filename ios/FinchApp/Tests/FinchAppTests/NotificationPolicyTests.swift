import XCTest
@testable import FinchApp

/// The rules that decide when an alert may interrupt someone.
///
/// Every case is a SPECIFIC instant built from components — never `Date()` — because the
/// interesting behaviour is "23:30 on a Tuesday", which a clock-reading type could not
/// express and a clock-reading test could not reproduce.
final class NotificationPolicyTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    private let quiet = QuietHours(startHour: 22, endHour: 8)

    // MARK: Delivery time

    func testOutsideQuietHoursIsImmediate() {
        let now = at(12, 14, 12)
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: now, quiet: quiet, calendar: cal), now)
    }

    func testEarlyMorningIsHeldToTheSameDay() {
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: at(12, 2, 14), quiet: quiet, calendar: cal),
                       at(12, 8))
    }

    /// The case a naive implementation fails: at 23:30 the window's end has ALREADY
    /// passed today, so "same date, hour = 8" would deliver it sixteen hours in the past.
    func testLateNightIsHeldToTheNextDay() {
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: at(12, 23, 30), quiet: quiet, calendar: cal),
                       at(13, 8))
    }

    /// Boundaries, stated: the start hour is quiet, the end hour is not.
    func testTheStartHourIsQuietAndTheEndHourIsNot() {
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: at(12, 22), quiet: quiet, calendar: cal),
                       at(13, 8), "22:00 exactly should be held")
        let eight = at(12, 8)
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: eight, quiet: quiet, calendar: cal),
                       eight, "08:00 exactly should go immediately")
    }

    /// A window that does NOT cross midnight must work too — the default happens to
    /// wrap, and an implementation written only for that shape inverts this one.
    func testAWindowInsideOneDay() {
        let nap = QuietHours(startHour: 1, endHour: 6)
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: at(12, 3), quiet: nap, calendar: cal),
                       at(12, 6), "inside the window is held")
        let noon = at(12, 12)
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: noon, quiet: nap, calendar: cal),
                       noon, "outside it is immediate")
        let midnight = at(12, 0)
        XCTAssertEqual(NotificationPolicy.deliveryTime(raisedAt: midnight, quiet: nap, calendar: cal),
                       midnight, "before the window starts is immediate, NOT held")
    }

    // MARK: Cap

    private func planned(_ n: Int) -> [PlannedNotification] {
        (0..<n).map { PlannedNotification(id: "p\($0)", kind: .anomaly, title: "t", body: "b",
                                          tab: nil, focusId: nil) }
    }

    private func summary(_ n: Int) -> PlannedNotification {
        PlannedNotification(id: "summary", kind: .anomaly, title: "More", body: "\(n) more",
                            tab: nil, focusId: nil)
    }

    func testUnderTheCapIsUntouchedAndMakesNoSummary() {
        let out = NotificationPolicy.applyCap(planned(2), cap: 3, summary: summary)
        XCTAssertEqual(out.map(\.id), ["p0", "p1"])
    }

    func testAtTheCapIsUntouched() {
        let out = NotificationPolicy.applyCap(planned(3), cap: 3, summary: summary)
        XCTAssertEqual(out.count, 3)
        XCTAssertFalse(out.contains { $0.id == "summary" })
    }

    func testOverTheCapKeepsTheCapAndSummarisesTheRest() {
        let out = NotificationPolicy.applyCap(planned(10), cap: 3, summary: summary)
        XCTAssertEqual(out.map(\.id), ["p0", "p1", "p2", "summary"])
        XCTAssertEqual(out.last?.body, "7 more", "the summary must report what it replaced")
    }
}

/// The planner's half of pre-scheduling.
final class ScheduledDuePlanningTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    /// A day string plus an hour, with a malformed day degrading to nil rather than
    /// crashing — a bad `nextRun` should mean "send now", not take the app down.
    func testDeliverAtBuildsTheDateAndToleratesRubbish() {
        XCTAssertEqual(NotificationPlanner.deliverAt("2026-09-01", hour: 9, cal),
                       cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9)))
        XCTAssertNil(NotificationPlanner.deliverAt("", hour: 9, cal))
        XCTAssertNil(NotificationPlanner.deliverAt("not-a-date", hour: 9, cal))
    }
}
