import SwiftUI
import FinchCore

/// The transaction row's swipe + context-menu actions, in ONE place.
///
/// These used to be copy-pasted across five lists (Activity, Account detail, and
/// the Category/Tag/Merchant detail views) and had drifted apart — the three
/// detail views offered neither Confirm nor Delete, so a pending transaction
/// couldn't be confirmed from them at all.
///
/// Layout, identical on every list:
///
///     swipe right → [ Duplicate ]                full swipe ⇒ Duplicate
///     swipe left  → [ Delete ][ Set pending ]    full swipe ⇒ status toggle
///
/// Both full-swipe gestures are deliberately the SAFE ones. Duplicate only opens
/// a pre-filled sheet (nothing is written until Save) and the status toggle is
/// reversible, so the fast imprecise gesture can't destroy anything. Delete sits
/// INBOARD — reachable only by a deliberate tap, which then raises a confirmation
/// alert. That keeps the long-standing "destructive actions get a confirm step"
/// rule while making it stricter than before, not looser.
///
/// The status toggle is declared FIRST because SwiftUI puts the first trailing
/// button at the edge and triggers it on a full swipe. Reversing these two lines
/// would silently make full-swipe-left mean Delete.
struct TxnSwipeActions: ViewModifier {
    let txn: Tx
    /// Open the pre-filled Add sheet. Duplicate never writes directly.
    let duplicate: (Tx) -> Void
    /// Stage the delete — the caller owns the confirmation alert (it must be
    /// window-level; a row-anchored popout gets torn down when the row recycles).
    let requestDelete: (Tx) -> Void
    /// Flip pending ⇄ confirmed.
    let toggleStatus: (Tx) -> Void
    /// Open the editor (context menu only — tapping the row already does this).
    let edit: (Tx) -> Void
    /// Receipt preview, context menu only. Pass nil when the row has no
    /// attachment (or the list doesn't support previews) and the item is omitted.
    var previewReceipt: ((Tx) -> Void)? = nil

    private var isPending: Bool { txn.pending == true }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                duplicateButton
            }
            // Delete only. The status action moved to the row's leading glyph in
            // `19f1d32a` — one tap, and no swipe left open while the row relocates,
            // which is where every artefact in #702 came from. Delete is now the
            // full-swipe action; it raises a confirmation rather than deleting, so that
            // is a dialog rather than data loss.
            .swipeActions(edge: .trailing) {
                deleteButton
            }
            .contextMenu {        // right-click parity on Mac/iPad (swipe is touch-only)
                Button { edit(txn) } label: { Label("Edit", systemImage: "pencil") }
                Button { duplicate(txn) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                if let previewReceipt {
                    Button { previewReceipt(txn) } label: { Label("Preview receipt", systemImage: "paperclip") }
                }
                Button { toggleStatus(txn) } label: { statusLabel }
                Button(role: .destructive) { requestDelete(txn) } label: { Label("Delete", systemImage: "trash") }
            }
    }

    // Duplicate is offered on EVERY kind. It used to be expense/income-only, but
    // that was a guard around an incomplete prefill (which mapped every non-income
    // kind to .expense), not a statement about which kinds are duplicable.
    private var duplicateButton: some View {
        SwipeButton("Duplicate", systemImage: "plus.square.on.square") { duplicate(txn) }
            .tint(.indigo)
    }

    @ViewBuilder private var statusLabel: some View {
        if isPending {
            Label("Confirm", systemImage: "checkmark.circle")
        } else {
            Label("Set pending", systemImage: "clock.badge.questionmark")
        }
    }

    // Deliberately NOT role: .destructive — that role plays a fake row-removal
    // animation on tap, which both looks like a premature delete and tears down
    // the row-anchored confirmation.
    private var deleteButton: some View {
        SwipeButton("Delete", systemImage: "trash") { requestDelete(txn) }
            .tint(.red)
    }
}

extension View {
    /// Attach the shared transaction row actions. Every list passes its own
    /// handlers — notably `requestDelete`, because the confirmation alert has to
    /// live on the hosting view.
    func txnSwipeActions(_ txn: Tx,
                         duplicate: @escaping (Tx) -> Void,
                         requestDelete: @escaping (Tx) -> Void,
                         toggleStatus: @escaping (Tx) -> Void,
                         edit: @escaping (Tx) -> Void,
                         previewReceipt: ((Tx) -> Void)? = nil) -> some View {
        modifier(TxnSwipeActions(txn: txn, duplicate: duplicate,
                                 requestDelete: requestDelete,
                                 toggleStatus: toggleStatus, edit: edit,
                                 previewReceipt: previewReceipt))
    }
}

/// Flip a transaction between pending and confirmed — the one implementation, so
/// the two directions can't drift apart.
///
/// The directions deliberately use DIFFERENT actions. Confirming keeps the
/// dedicated `confirmTransaction` (already used by bulk-confirm, the Siri intent
/// and Reconcile), so the long-standing Confirm gesture behaves exactly as before
/// — it's a targeted UPDATE guarded on `status = 'pending'`. Un-confirming has no
/// such action, so it patches status through `updateTransaction`: the same call
/// the Edit sheet's Status picker already makes, which nulls `confirmed_at` and
/// recomputes every touched account's cached balance.
///
/// Works for every kind including transfers — `updateTransfer` covers only
/// amounts/date/note, and status goes through this patch regardless.
@MainActor
func txnToggleStatus(_ txn: Tx, store: FinchStore) throws {
    if txn.pending == true {
        try store.apply(.confirmTransaction, Args(["id": .string(txn.id)]))
    } else {
        try store.apply(.updateTransaction, Args([
            "id": .string(txn.id),
            "patch": .object(["status": .string("pending")])]))
    }
}
