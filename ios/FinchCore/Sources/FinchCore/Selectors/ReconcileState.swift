import Foundation

/// Live reconcile tracker: how the cleared balance compares to the statement target.
public struct ReconcileState: Equatable, Sendable {
    public let clearedBalance: Double
    public let difference: Double      // statementBalance − clearedBalance
    public let balanced: Bool          // |difference| < 0.005
    public let clearedCount: Int
    public let unclearedCount: Int
    public init(clearedBalance: Double, difference: Double, balanced: Bool, clearedCount: Int, unclearedCount: Int) {
        self.clearedBalance = clearedBalance; self.difference = difference; self.balanced = balanced
        self.clearedCount = clearedCount; self.unclearedCount = unclearedCount
    }
}

extension Selectors {
    /// `statementBalance` and the result are in the account's native currency.
    /// clearedBalance = balance − Σ(confirmed, uncleared account-leg txns) — equals
    /// opening + Σ(confirmed cleared), since the opening leg is always cleared and the
    /// confirmed `balance` already includes it.
    public static func reconcileState(_ account: AccountRow, _ txns: [Tx], _ statementBalance: Double) -> ReconcileState {
        let acct = txns.filter { $0.account == account.id }
        let confirmed = acct.filter { $0.pending != true }
        let uncleared = confirmed.filter { $0.clearedAt == nil }
        let cleared = confirmed.filter { $0.clearedAt != nil }
        let nativeAmt: (Tx) -> Double = { $0.nativeAmount ?? $0.amount }
        let clearedBalance = r2(account.balance - uncleared.reduce(0) { $0 + nativeAmt($1) })
        let difference = r2(statementBalance - clearedBalance)
        return ReconcileState(
            clearedBalance: clearedBalance, difference: difference, balanced: abs(difference) < 0.005,
            clearedCount: cleared.count, unclearedCount: uncleared.count)
    }
}
