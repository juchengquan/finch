#if os(iOS)
import XCTest
import FinchCore
@testable import FinchApp

/// Which feed rows print their own date.
///
/// This exists because the rule is invisible when it breaks in the safe direction —
/// every row printing its date looks merely repetitive, not wrong — and because
/// driving the feed on the simulator to check it has proven unreliable (the taps that
/// reach it miss often enough that a red test is the cheaper signal). The rule itself
/// is duplicated from `ActivityTab.dateShownIds`, so it is exactly the kind of thing
/// that drifts silently.
final class TxRowDateRunTests: XCTestCase {

    /// Only `id` and `date` matter to the rule under test; everything else is filler.
    private func tx(_ id: String, _ date: String) -> Tx {
        Tx(id: id, merchant: "m", category: nil, amount: -1, account: "a",
           date: date, pending: nil, ledgerId: "l", currency: nil, nativeAmount: nil,
           time: nil, kind: "expense", transferGroupId: nil, counterpartyId: nil,
           splits: nil, tags: nil, note: nil, sourceTemplateId: nil,
           occurrenceDate: nil, refundedTransactionId: nil, clearedAt: nil,
           appliedRuleIds: nil, reviewedAt: nil)
    }

    /// One date per run of same-day rows — the first row of each run prints it.
    func testFirstOfEachDayRunPrintsTheDate() {
        let rows = [tx("a", "2026-07-29"), tx("b", "2026-07-29"),
                    tx("c", "2026-07-27"), tx("d", "2026-07-27"), tx("e", "2026-07-27"),
                    tx("f", "2026-07-26")]
        let shown = TxRowCell.dateShownIDs(pending: [], ordered: rows)
        XCTAssertEqual(shown, ["a", "c", "f"])
    }

    /// Pending rows always print theirs: they sit in their own bucket above the month
    /// sections, with no day-de-dup context around them.
    func testPendingAlwaysPrintTheirDate() {
        let pending = [tx("p1", "2026-07-29"), tx("p2", "2026-07-29")]
        let shown = TxRowCell.dateShownIDs(pending: pending, ordered: [tx("a", "2026-07-29")])
        XCTAssertTrue(shown.isSuperset(of: ["p1", "p2"]),
                      "both pending rows must carry their date even on the same day")
    }

    /// A date that recurs after a gap starts a NEW run and prints again — the rule is
    /// "differs from the row above", not "seen before". An out-of-order feed (a sort
    /// the user chose, say by amount) must not silently swallow dates.
    func testRepeatedDateAfterAGapPrintsAgain() {
        let rows = [tx("a", "2026-07-29"), tx("b", "2026-07-27"), tx("c", "2026-07-29")]
        let shown = TxRowCell.dateShownIDs(pending: [], ordered: rows)
        XCTAssertEqual(shown, ["a", "b", "c"])
    }

    func testEmptyInputProducesNothing() {
        XCTAssertTrue(TxRowCell.dateShownIDs(pending: [], ordered: []).isEmpty)
    }
}
#endif
