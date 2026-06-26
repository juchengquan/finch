import XCTest
@testable import FinchApp
import FinchCore

/// Phase 7 — the pure widget-data computations (the tested core; the WidgetKit /
/// Watch targets that render this are deferred infra).
final class WidgetSnapshotTests: XCTestCase {
    func test_netWorthSumsIncludedAccounts() {
        let accounts = [
            AccountRow(id: "a", balance: 100, includeInNetWorth: 1),
            AccountRow(id: "b", balance: 50, includeInNetWorth: 1),
            AccountRow(id: "c", balance: 999, includeInNetWorth: 0),   // excluded
        ]
        // identity conversion
        let nw = WidgetSnapshot.netWorth(accounts) { amt, _ in amt }
        XCTAssertEqual(nw, 150, accuracy: 0.001)
    }

    func test_budgetUsedPctZeroWhenNoBudgets() {
        XCTAssertEqual(WidgetSnapshot.budgetUsedPct([], [], "2026-05-15", []), 0)
    }

    func test_codableRoundTrip() throws {
        let snap = WidgetSnapshot(netWorth: 1234.5, currency: "USD", budgetUsedPct: 42,
                                  weeklySpent: 88.0, generatedAt: "2026-05-15T00:00:00Z")
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), snap)
    }

    func test_snapshot_carries_accounts_and_budgets() throws {
        let snap = WidgetSnapshot(
            netWorth: 100, currency: "USD", budgetUsedPct: 50, weeklySpent: 20, generatedAt: "t",
            accounts: [AccountSnapshotItem(id: "a1", name: "Checking", balance: 1240, currency: "USD")],
            budgets: [BudgetSnapshotItem(id: "b1", name: "Food", usedPct: 75)])
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snap))
        XCTAssertEqual(back.accounts?.map(\.id), ["a1"])
        XCTAssertEqual(back.accounts?.first?.balance, 1240)
        XCTAssertEqual(back.budgets?.first?.usedPct, 75)
    }

    func test_snapshot_back_compat_old_blob_without_arrays() throws {
        let old = #"{"netWorth":100,"currency":"USD","budgetUsedPct":50,"weeklySpent":20,"generatedAt":"t"}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(snap.accounts)
        XCTAssertNil(snap.budgets)
        XCTAssertEqual(snap.netWorth, 100)
    }
}
