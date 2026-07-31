import Foundation

/// Impact line for the merge confirmation, or `nil` when nothing combines. The
/// count is the choice-independent union of transactions referencing either
/// category, so the message is identical whichever name wins.
func mergeImpactMessage(txCount: Int) -> String? {
    guard txCount > 0 else { return nil }
    return txCount == 1
        ? String(localized: "1 transaction will be combined")
        : String(localized: "\(txCount) transactions will be combined")
}
