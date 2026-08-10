import XCTest
import FinchCore
@testable import FinchApp

/// The reconcile mode's pure logic (window / staged difference / diagnosis /
/// commit guard). Everything the parity gates don't cover — the engine is
/// untouched — so these tests carry the full weight, per the design doc.
final class ReconcileModeTests: XCTestCase {

    private func tx(_ id: String, date: String, amount: Double,
                    cleared: String? = nil, pending: Bool? = nil) -> Tx {
        var t = Tx(id: id, merchant: "M", category: nil, amount: amount,
                   account: "acct", date: date, pending: pending)
        t.clearedAt = cleared
        return t
    }
    private let account = AccountRow(id: "acct", balance: 100)

    // MARK: window

    func test_window_sections_respect_checkpoint_and_cut() {
        let txns = [
            tx("on-checkpoint", date: "2026-07-01", amount: -1),            // <= checkpoint, uncleared
            tx("in-period",     date: "2026-07-15", amount: -2),
            tx("on-cut",        date: "2026-07-31", amount: -3),            // inclusive upper bound
            tx("after-cut",     date: "2026-08-02", amount: -4),
            tx("settled-old",   date: "2026-06-10", amount: -5, cleared: "2026-07-01T00:00:00Z"),
            tx("settled-new",   date: "2026-07-20", amount: -6, cleared: "2026-08-01T00:00:00Z"),
        ]
        let w = ReconcileMode.window(txns: txns, accountId: "acct",
                                     lastReconciledAt: "2026-07-01", statementDate: "2026-07-31")
        XCTAssertEqual(w.inPeriod.map(\.id), ["in-period", "on-cut"])
        XCTAssertEqual(w.afterStatement.map(\.id), ["after-cut"])
        XCTAssertEqual(w.openFromBefore.map(\.id), ["on-checkpoint"])
        XCTAssertEqual(Set(w.settled.map(\.id)), ["settled-old", "settled-new"],
                       "cleared rows are settled regardless of date — the toggle's cargo")
    }

    func test_window_without_checkpoint_has_no_before_bucket() {
        let txns = [tx("ancient", date: "2020-01-01", amount: -1),
                    tx("recent", date: "2026-08-01", amount: -2)]
        let w = ReconcileMode.window(txns: txns, accountId: "acct",
                                     lastReconciledAt: nil, statementDate: "2026-08-10")
        XCTAssertEqual(w.inPeriod.map(\.id), ["ancient", "recent"],
                       "no checkpoint ⇒ the whole history is the first period")
        XCTAssertTrue(w.openFromBefore.isEmpty)
    }

    func test_window_ignores_other_accounts() {
        var foreign = tx("foreign", date: "2026-07-15", amount: -9)
        foreign.account = "other"
        let w = ReconcileMode.window(txns: [foreign], accountId: "acct",
                                     lastReconciledAt: nil, statementDate: "2026-07-31")
        XCTAssertEqual(w, ReconcileMode.Window())
    }

    // MARK: staged difference (zero writes while working)

    func test_staged_difference_overlays_ticks() {
        let txns = [
            tx("A", date: "2026-07-10", amount: -30, cleared: "2026-07-20T00:00:00Z"),
            tx("B", date: "2026-07-12", amount: -40),
        ]
        // Nothing staged: cleared = 100 − (−40 uncleared) = 140; stmt 100 ⇒ −40.
        XCTAssertEqual(ReconcileMode.stagedDifference(account: account, txns: txns,
                                                      staged: [], unstaged: [],
                                                      statementBalance: 100), -40)
        // Ticking B clears everything ⇒ difference 0.
        XCTAssertEqual(ReconcileMode.stagedDifference(account: account, txns: txns,
                                                      staged: ["B"], unstaged: [],
                                                      statementBalance: 100), 0)
        // Unticking the settled A while B stays ticked ⇒ A uncleared ⇒ −30.
        XCTAssertEqual(ReconcileMode.stagedDifference(account: account, txns: txns,
                                                      staged: ["B"], unstaged: ["A"],
                                                      statementBalance: 100), -30)
    }

    // MARK: diagnosis

    func test_diagnose_balanced() {
        XCTAssertEqual(ReconcileMode.diagnose(difference: 0, tickedRows: [], untickedRows: [], pendingRows: []),
                       .balanced)
    }

    func test_diagnose_positive_matches_a_ticked_row() {
        let ticked = [tx("hit", date: "2026-07-10", amount: -42.10),
                      tx("other", date: "2026-07-11", amount: -7)]
        XCTAssertEqual(ReconcileMode.diagnose(difference: 42.10, tickedRows: ticked,
                                              untickedRows: [], pendingRows: []),
                       .tickedTooMuch(matchId: "hit"))
    }

    func test_diagnose_negative_matches_unticked_then_pending() {
        let unticked = [tx("cold", date: "2026-07-10", amount: -42.10)]
        XCTAssertEqual(ReconcileMode.diagnose(difference: -42.10, tickedRows: [],
                                              untickedRows: unticked, pendingRows: []),
                       .missingFromFinch(matchId: "cold", addAmount: -42.10))
        let pending = [tx("maybe", date: "2026-07-10", amount: -42.10, pending: true)]
        XCTAssertEqual(ReconcileMode.diagnose(difference: -42.10, tickedRows: [],
                                              untickedRows: [], pendingRows: pending),
                       .missingFromFinch(matchId: "maybe", addAmount: -42.10),
                       "pending rows are candidates — confirming one closes the gap")
    }

    func test_diagnose_no_pair_false_positive() {
        // 20 + 20 sums to the gap but neither row matches alone — the doc rejects
        // pair matching because accepting it records two false clearings.
        let unticked = [tx("p1", date: "2026-07-10", amount: -20),
                        tx("p2", date: "2026-07-11", amount: -20)]
        XCTAssertEqual(ReconcileMode.diagnose(difference: -40, tickedRows: [],
                                              untickedRows: unticked, pendingRows: []),
                       .missingFromFinch(matchId: nil, addAmount: -40))
    }

    // MARK: commit guard

    func test_partial_batch_refuses_to_seal() {
        XCTAssertTrue(ReconcileMode.shouldSeal(applied: 5, expected: 5))
        XCTAssertFalse(ReconcileMode.shouldSeal(applied: 4, expected: 5),
                       "a short batch must refuse to seal — never widen the plug silently")
    }
}
