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
}
