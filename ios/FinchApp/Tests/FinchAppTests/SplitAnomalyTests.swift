import XCTest
@testable import FinchApp
import FinchCore

/// The anomaly alert scored a single payment leg against per-merchant statistics.
///
/// `Selectors.anomalyScore` takes one `Tx` and cannot see sibling legs, so it
/// cannot score a purchase — the fix belongs at its callers, not in it. The
/// planner is the one that reaches the user: it fired per leg, keyed the
/// notification on a posting id, and printed a leg's amount as though it were
/// what was spent.
final class SplitAnomalyTests: XCTestCase {
    private let money: (Double) -> String = { String(format: "%.0f", $0) }

    private func tx(_ id: String, _ amount: Double, entry: String, account: String = "a1") -> Tx {
        Tx(id: id, merchant: "Market", category: "c1", amount: amount, account: account,
           date: "2026-05-14", pending: false, ledgerId: "l1", currency: "USD",
           nativeAmount: amount, kind: "expense", entryId: entry)
    }

    /// Ten ordinary $10 purchases, then one $100 purchase paid $60 + $40.
    ///
    /// The margins are chosen so the bug is visible rather than incidental: scored
    /// per leg, the $60 leg clears the z-score threshold on its own and the $40 one
    /// does not — so the user got an alert naming $60, an amount they never spent
    /// in one go, while the real $100 purchase was never assessed as a whole.
    private func ledger() -> [Tx] {
        var txns = (0..<10).map { tx("p\($0)", -10, entry: "e\($0)") }
        txns.append(tx("split-a", -60, entry: "split"))
        txns.append(tx("split-b", -40, entry: "split", account: "a2"))
        return txns
    }

    func test_anomalyAlert_describesThePurchase_notOneOfItsPayments() {
        let planned = NotificationPlanner.plan(
            budgets: [], txns: ledger(), scheduled: [], categories: [],
            today: "2026-05-15", wallToday: "2026-05-15", ledgerId: "l1",
            enabled: [.anomaly], money: money)

        let anomalies = planned.filter { $0.kind == .anomaly }
        XCTAssertEqual(anomalies.count, 1, "one purchase is unusual, so one alert")
        let body = try! XCTUnwrap(anomalies.first?.body)
        XCTAssertTrue(body.contains("100"), "the alert must name the purchase's amount: \(body)")
        XCTAssertFalse(body.contains("60"), "not one of its payments: \(body)")
    }

    /// The notification id must be stable per purchase. Keyed on a posting id, a
    /// split purchase could raise two alerts for one event, and re-running the
    /// planner after an edit that re-keys a posting would leave a stale alert
    /// behind that `cancelIDs` never matches.
    func test_anomalyAlert_isKeyedOnThePurchase_notThePosting() {
        let planned = NotificationPlanner.plan(
            budgets: [], txns: ledger(), scheduled: [], categories: [],
            today: "2026-05-15", wallToday: "2026-05-15", ledgerId: "l1",
            enabled: [.anomaly], money: money)

        let ids = planned.filter { $0.kind == .anomaly }.map(\.id)
        XCTAssertEqual(ids, ["anomaly:split"], "one id, naming the entry rather than a posting")
    }
}
