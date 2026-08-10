import Foundation
import FinchCore

/// Pure logic for the in-place reconciliation mode (2026-08-10 design,
/// superseding the sheet on iOS — see plans/ios-macos/2026-08-10-reconcile-mode-design.md).
///
/// Everything here is display/staging computation over the projection — the
/// engine's `reconcileState`, `setCleared` and `reconcileAccount` keep their
/// semantics untouched, which is what keeps the parity surface at zero churn.

public enum ReconcileMode {

    /// The doc's window, adapted to the mode: settled rows (already cleared)
    /// are hidden behind the "show reconciled" toggle; everything else is
    /// unreconciled and grouped by where it stands relative to the statement.
    public struct Window: Equatable {
        public var inPeriod: [Tx] = []        // > checkpoint, <= statement cut
        public var afterStatement: [Tx] = []  // > cut — cannot be on this statement
        public var openFromBefore: [Tx] = []  // <= checkpoint, never cleared
        public var settled: [Tx] = []         // cleared — the toggle's cargo
    }

    public static func window(txns: [Tx], accountId: String,
                              lastReconciledAt: String?, statementDate: String) -> Window {
        var w = Window()
        for t in txns where t.account == accountId {
            if t.clearedAt != nil { w.settled.append(t); continue }
            if let cp = lastReconciledAt, t.date <= cp { w.openFromBefore.append(t) }
            else if t.date <= statementDate { w.inPeriod.append(t) }   // cut is inclusive
            else { w.afterStatement.append(t) }
        }
        return w
    }

    /// Difference with the staged ticks overlaid — zero writes while working.
    /// `staged` holds the ids the user has ticked THIS session; `unstaged`
    /// holds previously-cleared ids the user has unticked.
    public static func stagedDifference(account: AccountRow, txns: [Tx],
                                        staged: Set<String>, unstaged: Set<String>,
                                        statementBalance: Double) -> Double {
        // Overlay, don't write: the engine's own selector does the math over a
        // copy whose clearedAt reflects the session's staged state.
        var overlaid = txns
        for i in overlaid.indices {
            if staged.contains(overlaid[i].id) { overlaid[i].clearedAt = "staged" }
            else if unstaged.contains(overlaid[i].id) { overlaid[i].clearedAt = nil }
        }
        return Selectors.reconcileState(account, overlaid, statementBalance).difference
    }

    /// The doc's diagnosis: the sign names the direction, an exact single-amount
    /// match names the row, and only a no-match falls back to quick-add.
    public enum Diagnosis: Equatable {
        case balanced
        /// Positive difference: something ticked isn't on the statement.
        case tickedTooMuch(matchId: String?)
        /// Negative difference: the bank has something finch hasn't —
        /// a row to tick (or a pending row to confirm), else add the amount.
        case missingFromFinch(matchId: String?, addAmount: Double)
    }

    public static func diagnose(difference: Double,
                                tickedRows: [Tx], untickedRows: [Tx],
                                pendingRows: [Tx]) -> Diagnosis {
        // Exact single-amount match only — pair/fuzzy matching is REJECTED (see
        // the Aug 3 doc: round amounts collide, and a coincidental pair records
        // two false clearings). eps matches the engine's r2 cent-rounding.
        let eps = 0.005
        if abs(difference) < eps { return .balanced }
        let target = abs(difference)
        let matches: (Tx) -> Bool = { abs(abs($0.nativeAmount ?? $0.amount) - target) < eps }
        if difference > 0 {
            return .tickedTooMuch(matchId: tickedRows.first(where: matches)?.id)
        }
        let match = untickedRows.first(where: matches) ?? pendingRows.first(where: matches)
        return .missingFromFinch(matchId: match?.id, addAmount: difference)
    }

    /// The commit guard: a partial batch must refuse to seal (the doc's rule —
    /// never let the plug widen silently).
    public static func shouldSeal(applied: Int, expected: Int) -> Bool {
        applied == expected
    }
}
