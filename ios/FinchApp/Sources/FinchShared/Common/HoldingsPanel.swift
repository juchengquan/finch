import Foundation
import FinchCore

/// When the account screen shows investment positions, and when it offers to add one.
///
/// The rule lives here rather than inline in the two account screens because there are
/// two of them — `AccountDetailVC` on iOS and `AccountDetailView` on macOS and under
/// `-uikitActivity NO` — and a gating rule duplicated across both is a rule that drifts.
///
/// It is deliberately stricter than the web's, which gates on the account type alone.
enum HoldingsPanel {

    /// Visible on an investment account **even with no positions**: the "Add position"
    /// row is the only way to add the first one, so gating on the data alone would make
    /// the feature unreachable on exactly the accounts that need it.
    ///
    /// Visible on a NON-investment account that still carries positions, too. Two schema
    /// triggers stop holdings being *added* to one, but nothing stops `updateAccount`
    /// changing an account's type out from under existing positions — and a type-only
    /// gate would then strand rows that could be neither seen nor deleted. The web has
    /// exactly that hole.
    /// `accountType` is optional because `AccountRow.type` is — a row with no type is
    /// not an investment account, and only shows the section if it has positions.
    static func isVisible(accountType: String?, hasHoldings: Bool) -> Bool {
        accountType == "investment" || hasHoldings
    }

    /// The Add row is investment-only: the insert trigger rejects anything else, so
    /// offering it on a stranded-positions account would only raise an error alert.
    static func allowsAdding(accountType: String?) -> Bool {
        accountType == "investment"
    }

    /// Total unrealized gain/loss across the positions that have one.
    ///
    /// A position with no price has no gain/loss, so it is skipped rather than counted
    /// as zero; `nil` when none of them have a price, so the caller can drop the line
    /// entirely instead of stating a gain of zero it cannot vouch for.
    static func unrealizedTotal(_ holdings: [Holding]) -> Double? {
        let gains = holdings.compactMap { Selectors.holdingGainLoss($0) }
        return gains.isEmpty ? nil : gains.reduce(0, +)
    }
}
