import XCTest
@testable import FinchApp
import FinchCore

final class ReconcileReminderTests: XCTestCase {
    func test_rawMapping_offAndNegativeMeanNeverStale() {
        XCTAssertEqual(ReconcileReminder.staleDays(30), 30)
        XCTAssertEqual(ReconcileReminder.staleDays(0), Int.max)
        XCTAssertEqual(ReconcileReminder.staleDays(-5), Int.max)
    }

    func test_offKeepsAncientReconcileFresh() {
        let s = Selectors.reconcileStatus("2020-01-01", "2026-07-23",
                                          staleDays: ReconcileReminder.staleDays(0))
        guard case .fresh = s else { return XCTFail("Off must keep reconciled accounts fresh, got \(s)") }
    }

    func test_defaultCutoff_staleAfter30Days() {
        let cut = ReconcileReminder.staleDays(ReconcileReminder.defaultDays)
        guard case .fresh = Selectors.reconcileStatus("2026-06-23", "2026-07-23", staleDays: cut) else {
            return XCTFail("30 days ago at 30-day cutoff is still fresh")
        }
        guard case .stale = Selectors.reconcileStatus("2026-06-22", "2026-07-23", staleDays: cut) else {
            return XCTFail("31 days ago at 30-day cutoff is stale")
        }
    }
}
