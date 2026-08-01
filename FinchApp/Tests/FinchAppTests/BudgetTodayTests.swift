import XCTest
@testable import FinchApp
import FinchCore

/// Budget cycles follow the WALL CLOCK, not the newest transaction.
///
/// `FinchStore.today` is deliberately the newest transaction's date — inherited from
/// the web, whose reasons are demo determinism and avoiding a React hydration
/// mismatch. Budget windows used to use it, and the result was visible on a device:
/// with the newest transaction on 31 July, opening the app on 1 August showed JULY's
/// cycle — last month's spend and "0 days left" on every budget — because the
/// ledger's idea of today had not moved. Any quiet spell froze the cycle at the last
/// thing you recorded.
///
/// The fixture pack is the ideal case for this: its transactions are historical and
/// fixed, so `store.today` is always months behind the real date. A budget cycle read
/// from that lands in the pack's last month; read from the wall clock it lands in the
/// current one.
@MainActor
final class BudgetTodayTests: XCTestCase {

    private func samplePack() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        return try Data(contentsOf: url)
    }

    private func loadedStore() async throws -> FinchStore {
        let store = FinchStore()
        try await store.loadPack(from: try samplePack())
        return store
    }

    /// A plain recurring monthly budget, started well before any plausible "now".
    /// Constructed rather than fished out of the pack: the pack's budget set is not
    /// this test's subject, and depending on it made the test fail for the wrong
    /// reason (it carries no recurring monthly budget at all).
    private func monthlyBudget(ledgerId: String) -> BudgetRow {
        BudgetRow(id: "b-test", ledgerId: ledgerId, groupId: nil, name: "Test",
                  type: "expense", amount: 100, saved: 0, carryForward: 0,
                  frequency: "monthly", startDate: "2020-01-01", endDate: nil,
                  isRecurring: 1, rollover: 0, rolloverLimit: nil, pendingAmount: nil,
                  lastRolledPeriod: nil, accountIds: [], categoryIds: [], warningPct: 80)
    }

    /// The premise: this pack really is historical, so the two dates differ. Without
    /// this the tests below could pass for the wrong reason.
    func test_thePackIsHistorical_soTheTwoDatesDiffer() async throws {
        let store = try await loadedStore()
        XCTAssertFalse(store.txns.isEmpty, "the pack should carry transactions")
        XCTAssertNotEqual(store.today, store.wallToday,
                          "fixture is dated today — this suite cannot prove anything")
    }

    func test_budgetToday_isTheWallClock_notTheNewestTransaction() async throws {
        let store = try await loadedStore()
        XCTAssertEqual(store.budgetToday, store.wallToday)
        XCTAssertNotEqual(store.budgetToday, store.today,
                          "budget cycles are back on the data — the 1st-of-month bug returns")
    }

    /// The bug as a user meets it: a live monthly budget's cycle must be the CURRENT
    /// calendar month. Anchored on the data it was the pack's last month instead.
    func test_monthlyBudgetCycleIsTheCurrentCalendarMonth() async throws {
        let store = try await loadedStore()
        let budget = monthlyBudget(ledgerId: store.activeLedgerId)

        let cycle = Selectors.budgetProgress(budget, store.txns, store.budgetToday, store.categoryNodes)

        XCTAssertEqual(String(cycle.from.prefix(7)), String(store.wallToday.prefix(7)),
                       "cycle starts in \(cycle.from), not the current month")
        XCTAssertEqual(String(cycle.to.prefix(7)), String(store.wallToday.prefix(7)),
                       "cycle ends in \(cycle.to), not the current month")
    }

    /// And the symptom that was reported: a live cycle cannot already be over.
    /// `daysLeft` is 0 only on the cycle's final day, so assert against the window
    /// rather than a magic number.
    func test_aLiveCycleHasNotAlreadyEnded() async throws {
        let store = try await loadedStore()
        let budget = monthlyBudget(ledgerId: store.activeLedgerId)

        let cycle = Selectors.budgetProgress(budget, store.txns, store.budgetToday, store.categoryNodes)

        XCTAssertGreaterThanOrEqual(cycle.to, store.wallToday,
                                    "the cycle ended on \(cycle.to), before today — it is last month's")
        XCTAssertLessThanOrEqual(cycle.from, store.wallToday,
                                 "the cycle starts on \(cycle.from), after today — it is next month's")
    }

    // MARK: - "days left" counts today, from the wall clock

    private func day(offsetFromToday days: Int) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date().addingTimeInterval(Double(days) * 86_400))
    }

    /// A cycle's FINAL day must read "1 day left", not "0". Counting only the days
    /// after today made a live, still-spendable cycle look finished — the reading
    /// that started this whole investigation.
    func test_daysLeft_countsTodayItself() async throws {
        let store = try await loadedStore()
        XCTAssertEqual(store.daysLeft(until: store.wallToday), 1)
    }

    func test_daysLeft_isZeroOncePast() async throws {
        let store = try await loadedStore()
        XCTAssertEqual(store.daysLeft(until: day(offsetFromToday: -1)), 0)
    }

    /// The device report: on 1 August, budgets read "32 days left" in a month with 31
    /// days, because the count was measured from the newest TRANSACTION (30 July)
    /// while the cycle came from the calendar. Anchored consistently, a count can
    /// never exceed the cycle's own length.
    func test_daysLeft_neverExceedsTheCycleLength() async throws {
        let store = try await loadedStore()
        let budget = monthlyBudget(ledgerId: store.activeLedgerId)
        let cycle = Selectors.budgetProgress(budget, store.txns, store.budgetToday, store.categoryNodes)

        let left = store.daysLeft(until: cycle.to)
        let cal = Calendar(identifier: .gregorian)
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 31

        XCTAssertGreaterThanOrEqual(left, 1, "a live cycle always has today left")
        XCTAssertLessThanOrEqual(left, daysInMonth,
                                 "\(left) days left in a \(daysInMonth)-day month — the count is anchored elsewhere")
    }


    // MARK: - hours on the final day

    /// The final day reports HOURS, not "1 day left" — which is the whole point of
    /// the finer unit: on the last day you want to know whether you have all evening
    /// or twenty minutes.
    func test_remaining_onTheFinalDay_isHours() async throws {
        let store = try await loadedStore()
        switch store.remaining(until: store.wallToday) {
        case .hours(let h):
            XCTAssertGreaterThanOrEqual(h, 1)
            XCTAssertLessThanOrEqual(h, 23, "a whole day should have been reported as days")
        case .lessThanAnHour:
            break   // legitimate if this runs in the last hour before midnight
        case .days(let d):
            XCTFail("the final day reported \(d) day(s) instead of hours")
        case .ended:
            XCTFail("today is not over")
        }
    }

    func test_remaining_pastCycleHasEnded() async throws {
        let store = try await loadedStore()
        XCTAssertEqual(store.remaining(until: day(offsetFromToday: -1)), .ended)
    }

    /// Above a day it stays in days, and agrees with `daysLeft` — the finer unit
    /// must not change the count people already read.
    func test_remaining_aboveADay_staysInDaysAndMatchesDaysLeft() async throws {
        let store = try await loadedStore()
        let target = day(offsetFromToday: 30)
        guard case .days(let d) = store.remaining(until: target) else {
            return XCTFail("30 days out should report days")
        }
        XCTAssertEqual(d, store.daysLeft(until: target))
    }

    // MARK: - a turnover time moves the finish line

    /// A fixed "now" so these read the same at 09:00 and at 23:50 — the difference
    /// under test is hours wide, and the wall clock would decide the answer.
    private func noonToday() throws -> (now: Date, target: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let noon = try XCTUnwrap(cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()))
        return (noon, AppDate.isoDay.string(from: noon))
    }

    /// With a turnover time the cycle stops at that moment ON `to`, not at the end
    /// of that day. Counting to the end would hand back up to a day the budget does
    /// not have — the same overstatement this helper exists to prevent.
    func test_remaining_stopsAtTheTurnover_notTheEndOfTheDay() async throws {
        let store = try await loadedStore()
        let (now, today) = try noonToday()

        // Untimed: noon → midnight is 12 hours.
        XCTAssertEqual(store.remaining(until: today, now: now), .hours(12))
        // Turning over at 18:00 leaves 6 of those, not 12.
        XCTAssertEqual(store.remaining(until: today, toTime: "18:00", now: now), .hours(6))
        // And a turnover already past means the cycle is over, whatever the date says.
        XCTAssertEqual(store.remaining(until: today, toTime: "09:30", now: now), .ended)
    }

    /// "00:00" is midnight, which is what an untimed cycle already ends at — so it
    /// must not shift the count. (The engine normalises it the same way.)
    func test_remaining_midnightMatchesNoTimeAtAll() async throws {
        let store = try await loadedStore()
        let (now, today) = try noonToday()
        XCTAssertEqual(store.remaining(until: today, toTime: "00:00", now: now),
                       store.remaining(until: today, now: now))
    }

}
