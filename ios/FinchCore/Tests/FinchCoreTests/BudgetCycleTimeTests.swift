import XCTest
@testable import FinchCore

/// A budget cycle can turn over at a time of day, not just at midnight.
///
/// The rule: a cycle is `[start moment, next start moment)`. With no time — every
/// budget until one is set — that collapses to the inclusive whole-day window the
/// selector has always produced, which the untimed cases below pin.
final class BudgetCycleTimeTests: XCTestCase {

    private func budget(startDate: String, startTime: String?) -> BudgetRow {
        BudgetRow(id: "b1", ledgerId: "l1", groupId: nil, name: "Food", type: "expense",
                  amount: 300, saved: 0, carryForward: 0, frequency: "monthly",
                  startDate: startDate, startTime: startTime, endDate: nil, endTime: nil,
                  isRecurring: 1, rollover: 0, rolloverLimit: nil, pendingAmount: nil,
                  lastRolledPeriod: nil, accountIds: [], categoryIds: [], warningPct: 80)
    }

    private func tx(_ date: String, _ time: String?, _ amount: Double) -> Tx {
        Tx(id: "t-\(date)-\(time ?? "x")", merchant: "m", category: "food", amount: amount,
           account: "a1", date: date, pending: false, ledgerId: "l1", time: time)
    }

    // MARK: untimed — unchanged

    func test_noTime_isTheWholeDayWindowItAlwaysWas() {
        let w = Selectors.cycleWindow("monthly", "2026-05-01", "2026-08-15", nil, 1, nil)
        XCTAssertEqual(w.from, "2026-08-01")
        XCTAssertEqual(w.to, "2026-08-31")
        XCTAssertNil(w.fromTime, "an untimed window must encode exactly as before")
        XCTAssertNil(w.toTime)
    }

    // MARK: timed

    func test_aTimedCycleRunsFromItsMomentToTheNext() {
        let w = Selectors.cycleWindow("monthly", "2026-05-01", "2026-08-15 10:00", nil, 1, "09:30")
        XCTAssertEqual(w.from, "2026-08-01")
        XCTAssertEqual(w.to, "2026-09-01", "the cycle stops on the day the next one starts")
        XCTAssertEqual(w.fromTime, "09:30")
        XCTAssertEqual(w.toTime, "09:30")
    }

    /// The turnover is a moment, so the morning of the 1st still belongs to the
    /// cycle that has not yet rolled.
    func test_beforeTheTurnover_theCycleHasNotRolled() {
        let w = Selectors.cycleWindow("monthly", "2026-05-01", "2026-08-01 09:00", nil, 1, "09:30")
        XCTAssertEqual(w.from, "2026-07-01", "09:00 on the 1st is still July's cycle")
        XCTAssertEqual(w.to, "2026-08-01")
    }

    func test_atTheTurnover_theCycleHasRolled() {
        let w = Selectors.cycleWindow("monthly", "2026-05-01", "2026-08-01 09:30", nil, 1, "09:30")
        XCTAssertEqual(w.from, "2026-08-01", "the turnover moment belongs to the NEW cycle")
    }

    // MARK: spending lands in the right cycle

    func test_spendingIsSplitByTheTurnoverMoment() {
        let b = budget(startDate: "2026-05-01", startTime: "09:30")
        let txns = [
            tx("2026-08-01", "09:00", -10),   // before the turnover -> July's cycle
            tx("2026-08-01", "10:00", -20),   // after  -> August's
            tx("2026-09-01", "09:00", -40),   // before September's turnover -> still August's
            tx("2026-09-01", "09:30", -80),   // at it -> September's
        ]
        let p = Selectors.budgetProgress(b, txns, "2026-08-15 12:00")
        XCTAssertEqual(p.used, 60, accuracy: 0.001,
                       "expected the 10:00 on 1 Aug and the 09:00 on 1 Sep, and nothing else")
    }

    /// A transaction with no time of its own reads as midnight — the same
    /// assumption the untimed path makes.
    func test_aTransactionWithoutATimeReadsAsMidnight() {
        let b = budget(startDate: "2026-05-01", startTime: "09:30")
        let p = Selectors.budgetProgress(b, [tx("2026-08-01", nil, -25)], "2026-08-15 12:00")
        XCTAssertEqual(p.used, 0, accuracy: 0.001, "midnight on the 1st is before a 09:30 turnover")
    }

    // MARK: midnight is not a time

    /// The sheet's picker always produces a time, so a budget saved without
    /// touching it stores "00:00". That has to mean what it says — a cycle running
    /// midnight to midnight — and NOT take the timed branch, whose `to` is the next
    /// start day. Otherwise every budget saved from the sheet would report a day
    /// more than it has: the "32 days left in a 31-day month" bug, reintroduced.
    func test_midnightIsIdenticalToNoTimeAtAll() {
        let untimed = Selectors.cycleWindow("monthly", "2026-05-01", "2026-08-15")
        let midnight = Selectors.cycleWindow("monthly", "2026-05-01", "2026-08-15", nil, 1, "00:00")
        XCTAssertEqual(midnight.from, untimed.from)
        XCTAssertEqual(midnight.to, untimed.to, "\"00:00\" took the timed branch — `to` moved by a day")
        XCTAssertNil(midnight.toTime)
    }

    // MARK: the History chart agrees with the header

    /// The detail page shows a bar per cycle above the current-cycle figure. They
    /// are computed by different code, so a turnover honoured by one and not the
    /// other puts the same spending in two different months — visibly, side by side.
    func test_historyCyclesUseTheSameBoundaryAsTheHeader() {
        let b = budget(startDate: "2026-05-01", startTime: "09:30")
        let txns = [tx("2026-08-01", "09:00", -10),    // July's cycle
                    tx("2026-08-01", "10:00", -20)]    // August's
        let today = "2026-08-15 12:00"

        let header = Selectors.budgetProgress(b, txns, today)
        let history = Selectors.budgetCycleHistory(b, txns, today)
        let current = try? XCTUnwrap(history.last)

        XCTAssertEqual(current?.isCurrent, true)
        XCTAssertEqual(current?.from, header.from)
        XCTAssertEqual(current?.to, header.to)
        XCTAssertEqual(current?.used ?? -1, header.used, accuracy: 0.001,
                       "the chart's current bar disagrees with the figure printed above it")
        XCTAssertEqual(current?.used ?? -1, 20, accuracy: 0.001)
    }

    // MARK: the write path

    /// The selector above is only reachable if the time SURVIVES a create. It is a
    /// new column on an INSERT that already had twenty of them, which is exactly the
    /// kind of place a value gets dropped silently.
    func test_createBudget_persistsTheStartTime() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Lunch"),
            "type": .string("expense"), "amount": .double(120), "frequency": .string("monthly"),
            "startDate": .string("2026-05-01"), "startTime": .string("09:30"),
        ]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT start_time FROM budgets WHERE id='b1'"), "09:30")
        }
    }

    /// Omitting it stores NULL rather than a "00:00" that would look identical but
    /// take the timed branch — the whole design rests on NULL meaning "as before".
    func test_createBudget_withoutATime_storesNull() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Food"),
            "type": .string("expense"), "amount": .double(300), "frequency": .string("monthly"),
            "startDate": .string("2026-05-01"),
        ]))
        try q.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT start_time FROM budgets WHERE id='b1'"))
        }
    }

    /// Changing the cycle is a separate action from editing the budget, and the
    /// turnover time belongs to the cycle — so it has to travel on that patch too.
    func test_updateBudgetCycle_carriesTheStartTime() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Food"),
            "type": .string("expense"), "amount": .double(300), "frequency": .string("monthly"),
            "startDate": .string("2026-05-01"),
        ]))
        try Apply.apply(dbQueue: q, action: "updateBudgetCycle", args: Args(["id": .string("b1"), "patch": .object([
            "frequency": .string("monthly"), "startDate": .string("2026-06-01"), "startTime": .string("07:15"),
        ])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT start_time FROM budgets WHERE id='b1'"), "07:15")
        }
    }

    /// A malformed time is rejected rather than stored: the cycle window compares
    /// times as plain strings, so "9:30" would sort after "10:00" and quietly put
    /// spending in the wrong month.
    func test_updateBudgetCycle_rejectsAMalformedTime() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Food"),
            "type": .string("expense"), "amount": .double(300), "frequency": .string("monthly"),
            "startDate": .string("2026-05-01"),
        ]))
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "updateBudgetCycle", args: Args([
            "id": .string("b1"), "patch": .object([
                "frequency": .string("monthly"), "startDate": .string("2026-06-01"), "startTime": .string("9:30"),
            ])])))
    }
}
