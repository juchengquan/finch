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
}
