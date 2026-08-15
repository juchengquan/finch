import Foundation

/// The one non-obvious rule in the ledger reorder mode: keeping the in-flight draft
/// honest while the store changes underneath it.
///
/// `LedgersVC` holds the dragged order as a plain `[String]` until ✓ — ledgers have no
/// groups and nothing nests, so unlike `AccountReorder`/`BudgetReorder` there is no row
/// model and no drop math to own. What IS worth pinning down is what happens when the
/// set of ledgers changes mid-drag: an import, a CloudKit down-sync or a widget write
/// can add or remove one while the mode is open, and both failure modes are silent.
/// A dropped id names a row that no longer exists; a missed id is invisible until ✓ and
/// then absent from the very list ✓ writes.
public enum LedgerReorder {

    /// Reconcile `draft` against the ledgers that actually exist.
    ///
    /// Ids still present keep the user's dragged order; ids that vanished are dropped;
    /// ids that appeared join at the end, in `live` order. Idempotent, so it can run on
    /// every republish.
    public static func reconciled(draft: [String], live: [String]) -> [String] {
        let liveSet = Set(live)
        var seen = Set<String>()
        // `seen` also collapses a duplicate in the draft: two rows with one id would
        // crash the diffable data source, not merely look wrong.
        let kept = draft.filter { liveSet.contains($0) && seen.insert($0).inserted }
        return kept + live.filter { !seen.contains($0) }
    }
}
