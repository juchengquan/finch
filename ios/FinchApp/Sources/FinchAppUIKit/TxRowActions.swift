#if os(iOS)
import UIKit
import FinchCore

/// The UIKit half of `TxnSwipeActions` — the transaction row's gestures in ONE
/// place, for the same reason the SwiftUI modifier exists: these were once
/// copy-pasted across five lists and had silently drifted apart.
///
/// Layout, identical to the SwiftUI modifier:
///
///     swipe right → [ Duplicate ]                full swipe ⇒ Duplicate
///     swipe left  → [ status ][ Delete ]         full swipe ⇒ status toggle
///
/// The status action is declared FIRST because UIKit, like SwiftUI, puts the
/// first action at the swiped edge and runs it on a full swipe. Reversing these
/// two lines would make a careless full swipe mean Delete.
struct TxRowActions {
    /// Opens the pre-filled Add sheet. Duplicate never writes directly.
    let duplicate: (Tx) -> Void
    /// Stages the delete; the caller owns the confirmation alert.
    let requestDelete: (Tx) -> Void
    /// Flips pending ⇄ confirmed.
    let toggleStatus: (Tx) -> Void
    /// Opens the editor (menu only — tapping the row already does this).
    let edit: (Tx) -> Void
    /// Receipt preview, menu only; nil when the row has no attachment.
    var previewReceipt: ((Tx) -> Void)?

    /// **No status action on the swipe — tapping the row's glyph does that.**
    ///
    /// It used to be here, and it was the source of everything in #702. A swipe action
    /// writes synchronously, so the row relocated (confirm/un-confirm moves it between
    /// the pending bucket and the dated list) while UIKit was still closing the swipe:
    /// red and orange buttons appeared inside "To confirm", where they mean nothing,
    /// and faded out there. Four attempts went at that race from different angles —
    /// close first, close instantly, animate the move, delay the write past a
    /// hard-coded 0.33s — and each traded one artefact for another.
    ///
    /// `19f1d32a` made the leading glyph the control instead: one tap, no gesture to
    /// close, nothing playing while the row moves. With it there, the swipe copy was
    /// redundant AND the expensive one, so it is gone and the timing constant with it.
    ///
    /// The action survives in three places, which is plenty: the glyph, the context
    /// menu below, and the row's accessibility custom action. Bulk confirm is separate.
    ///
    /// **This does not close #702.** The row still relocates on a glyph tap, and the
    /// device flicker reported there was never diagnosed — it may simply follow the
    /// user to the new gesture. What has gone is the swipe-close race specifically.
    func leading(_ tx: Tx) -> UISwipeActionsConfiguration {
        let dup = UIContextualAction(style: .normal, title: String(localized: "Duplicate")) { _, _, done in
            // Duplicate opens a pre-filled Add sheet and never moves the row, so there
            // is no relocation to race and nothing to wait for. It used to sit behind
            // the same 0.33s delay as the status action, which protected it from an
            // artefact it could not produce — a third of a second of dead time.
            done(true)
            duplicate(tx)
        }
        dup.image = UIImage(systemName: "plus.square.on.square")
        dup.backgroundColor = .systemIndigo
        return UISwipeActionsConfiguration(actions: [dup])
    }

    /// Delete only, now that the status action has moved to the glyph.
    ///
    /// Delete is therefore the FIRST action, which makes it the full-swipe action — the
    /// arrangement the previous comment here warned against ("a careless full swipe
    /// would mean Delete"). That warning was written when Delete deleted. It does not:
    /// every screen routes `requestDelete` to a confirmation alert, so a full swipe
    /// raises a dialog rather than destroying anything, and `done(false)` leaves the row
    /// in place until that dialog is answered.
    func trailing(_ tx: Tx) -> UISwipeActionsConfiguration {
        // Deliberately `.normal`, not `.destructive`: the destructive style plays a
        // row-removal animation on tap, which looks like the delete already happened
        // and tears the row down before the confirmation is answered.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { _, _, done in
            requestDelete(tx)
            done(false)   // the row stays until the alert is answered
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed

        return UISwipeActionsConfiguration(actions: [delete])
    }

    /// Right-click / long-press parity, matching the SwiftUI `.contextMenu`.
    func menu(_ tx: Tx) -> UIMenu {
        var items: [UIMenuElement] = [
            UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { _ in edit(tx) },
            UIAction(title: String(localized: "Duplicate"),
                     image: UIImage(systemName: "plus.square.on.square")) { _ in duplicate(tx) },
        ]
        if let previewReceipt {
            items.append(UIAction(title: String(localized: "Preview receipt"),
                                  image: UIImage(systemName: "paperclip")) { _ in previewReceipt(tx) })
        }
        let pending = tx.pending == true
        items.append(UIAction(title: statusTitle(pending),
                              image: UIImage(systemName: pending ? "checkmark.circle" : "clock.badge.questionmark")) { _ in
            toggleStatus(tx)
        })
        items.append(UIAction(title: String(localized: "Delete"),
                              image: UIImage(systemName: "trash"),
                              attributes: .destructive) { _ in requestDelete(tx) })
        return UIMenu(children: items)
    }

    private func statusTitle(_ pending: Bool) -> String {
        pending ? String(localized: "Confirm") : String(localized: "Set pending")
    }
}
#endif
