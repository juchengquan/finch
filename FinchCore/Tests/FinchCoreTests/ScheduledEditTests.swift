import XCTest
import GRDB
@testable import FinchCore

/// updateScheduled (the iOS edit sheet) + the categoryId now exposed on the
/// ScheduledTemplate projection (needed to prefill the edit form's category).
final class ScheduledEditTests: XCTestCase {
    private func seededTemplate() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"),
            "type": .string("expense"), "amount": .double(1000), "frequency": .string("monthly"),
            "dayOfMonth": .int(1), "accountId": .string("a1"), "category": .string("c1"),
            "startDate": .string("2026-01-01"),
        ]))
        return q
    }

    func test_categoryIdIsProjected() throws {
        let q = try seededTemplate()
        let t = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }
        XCTAssertEqual(t?.categoryId, "c1")
    }

    func test_updateScheduled_patches() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object([
            "name": .string("Mortgage"), "amount": .double(1200), "frequency": .string("weekly"),
        ])]))
        let t = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }!
        XCTAssertEqual(t.name, "Mortgage")
        XCTAssertEqual(t.amount ?? 0, 1200, accuracy: 0.001)
        XCTAssertEqual(t.frequency, "weekly")
    }

    func test_updateScheduled_clearsInstallmentWithNull() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object(["installmentTotal": .int(12)])]))
        XCTAssertEqual(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }?.installmentTotal, 12)
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object(["installmentTotal": .null])]))
        XCTAssertNil(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }?.installmentTotal ?? nil)
    }

    // MARK: - the start date is editable, and it moves the schedule

    /// The sheet used to show Start read-only, with a comment saying the engine
    /// omitted it — and it did: `startDate` was missing from the patchable columns,
    /// so the value was silently dropped. Editing a schedule's start is the whole
    /// point of editing a schedule.
    func test_updateScheduled_patchesTheStartDate() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object([
            "startDate": .string("2026-03-15"),
        ])]))
        let t = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }!
        XCTAssertEqual(t.startDate, "2026-03-15")
    }

    /// And moving it MOVES the schedule. Occurrences are derived from the start
    /// (`Forecast.occurrencesUpTo` anchors on it) and `next_run` is never written, so
    /// there is nothing stored to recompute — this asserts the derivation follows.
    func test_movingTheStartMovesTheOccurrences() throws {
        let q = try seededTemplate()
        let before = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }!
        let occBefore = Selectors.occurrencesUpTo(before, "2026-04-30")
        XCTAssertEqual(occBefore.first, "2026-01-01", "seeded schedule should start in January")

        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object([
            "startDate": .string("2026-03-15"),
        ])]))

        let after = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }!
        let occAfter = Selectors.occurrencesUpTo(after, "2026-04-30")

        // NOT 15 March: this schedule is monthly on DAY 1, so the start is an anchor,
        // not itself an occurrence. The first day-1 on or after 15 March is 1 April.
        XCTAssertEqual(occAfter.first, "2026-04-01", "the schedule did not move with its start date")
        XCTAssertFalse(occAfter.contains("2026-01-01"), "occurrences before the new start are still being produced")
        XCTAssertFalse(occAfter.contains("2026-03-01"), "an occurrence before the new start survived")
    }


    // MARK: - the intended time-of-day (phase 2)

    /// Every posting carries a time now — the intended one, or the firing moment.
    ///
    /// Without one the entry sinks to the BOTTOM of its day: the feed orders by
    /// `date DESC, time DESC` and SQLite sorts NULLs last, which is exactly what
    /// `AddTransactionSheet` avoids when it prefills an occurrence. The automatic
    /// path used to cause it.
    ///
    /// Determinism comes from the caller, not a clock seam: the app omits the time
    /// and gets "now", while the parity fixture PINS it — the same shape the action's
    /// `date` already uses.
    func test_postScheduled_withoutAnIntendedTime_stampsTheFiringMoment() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string("2026-02-01"),
        ]))
        let time = try q.read { db in
            try String.fetchOne(db, sql: "SELECT time FROM entries WHERE source_template_id = 's1'")
        }
        XCTAssertEqual(time?.count, 5, "expected HH:mm, got \(time ?? "nil") — a null time sinks the row")
    }

    /// An explicit time wins over both — this is what the fixture uses.
    func test_postScheduled_honoursAnExplicitTime() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string("2026-02-01"), "time": .string("11:22"),
        ]))
        let time = try q.read { db in
            try String.fetchOne(db, sql: "SELECT time FROM entries WHERE source_template_id = 's1'")
        }
        XCTAssertEqual(time, "11:22")
    }

    /// And when the template says WHEN, the posting uses it.
    func test_postScheduled_usesTheTemplatesIntendedTime() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object([
            "startTime": .string("09:30"),
        ])]))
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args([
            "templateId": .string("s1"), "date": .string("2026-02-01"),
        ]))
        let time = try q.read { db in
            try String.fetchOne(db, sql: "SELECT time FROM entries WHERE source_template_id = 's1'")
        }
        XCTAssertEqual(time, "09:30")
    }

    func test_startTime_isProjected() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object([
            "startTime": .string("07:05"),
        ])]))
        let t = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }
        XCTAssertEqual(t?.startTime, "07:05")
    }

}
