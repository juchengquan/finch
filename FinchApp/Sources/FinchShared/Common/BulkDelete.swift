import Foundation
import FinchCore

/// What deleting a multi-select will do, worked out before it happens — shared
/// by the iPhone feed (`ActivityFeedVC`) and the SwiftUI one (`ActivityTab`), so
/// the two confirmations cannot disagree about what they warn of.
public enum BulkDelete {
    /// Whether deleting `selected` would also remove rows the user did not tick.
    ///
    /// `selected` holds Tx ids — account-posting ids, one per feed row — but a
    /// delete takes the whole ENTRY: ticking one payment of a split-tender
    /// purchase, or one side of a transfer, takes its other legs with it.
    ///
    /// Keyed on the entry, not `purchaseKey`: a grid purchase is several entries
    /// sharing a group, and deleting one member deliberately leaves the others
    /// standing (Decision 19), so warning about them would be a false alarm.
    public static func takesUnselectedRows(_ selected: Set<String>, in txns: [Tx]) -> Bool {
        let entries = Set(txns.lazy.filter { selected.contains($0.id) }.map(entryKey))
        return txns.contains { entries.contains(entryKey($0)) && !selected.contains($0.id) }
    }

    /// The confirmation's title. Counts what was SELECTED — what the user sees
    /// ticked — even when the delete takes more; the message says so instead.
    /// (Two numbers disagreeing on one dialog reads as a bug.)
    public static func confirmTitle(_ count: Int) -> String {
        String(localized: "Delete \(count) transaction\(count == 1 ? "" : "s")?")
    }

    private static func entryKey(_ tx: Tx) -> String { tx.entryId ?? tx.id }
}
