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

    /// **Why every mutating action closes the swipe BEFORE it mutates.**
    ///
    /// These handlers write synchronously: `toggleStatus` reaches the store, the
    /// store republishes, and the list applies a new snapshot — all inside the
    /// closure. So the row had already been relocated (confirm/un-confirm moves it
    /// between the pending bucket and the dated list) by the time `done(true)` asked
    /// UIKit to close the swipe. The close animation then played on a cell that was
    /// somewhere else: red and orange action buttons appeared inside "To confirm",
    /// where they mean nothing, and faded out there over ~300ms.
    ///
    /// That is what a device report called "the animation looks ugly", and it is not
    /// about the row's motion at all — two attempts to animate the MOVE both made it
    /// worse, because they gave the stray buttons longer on screen. Frame analysis of
    /// a screen recording is what separated the two (see #702).
    ///
    /// `done` first, mutation on the next runloop turn: the swipe closes against the
    /// row where the user left it, and the data change lands after.
    func leading(_ tx: Tx) -> UISwipeActionsConfiguration {
        let dup = UIContextualAction(style: .normal, title: String(localized: "Duplicate")) { _, _, done in
            // Close WITHOUT animation, so nothing is still playing when the row
            // relocates. `done(true)` alone starts a ~300ms close; the mutation then
            // lands inside that window and the animation finishes at the row's NEW
            // position, painting action buttons into the section it moved to.
            UIView.performWithoutAnimation { done(true) }
            DispatchQueue.main.async { duplicate(tx) }
        }
        dup.image = UIImage(systemName: "plus.square.on.square")
        dup.backgroundColor = .systemIndigo
        return UISwipeActionsConfiguration(actions: [dup])
    }

    func trailing(_ tx: Tx) -> UISwipeActionsConfiguration {
        let pending = tx.pending == true
        let status = UIContextualAction(style: .normal, title: statusTitle(pending)) { _, _, done in
            // Close WITHOUT animation, so nothing is still playing when the row
            // relocates. `done(true)` alone starts a ~300ms close; the mutation then
            // lands inside that window and the animation finishes at the row's NEW
            // position, painting action buttons into the section it moved to.
            UIView.performWithoutAnimation { done(true) }
            DispatchQueue.main.async { toggleStatus(tx) }
        }
        status.image = UIImage(systemName: pending ? "checkmark.circle" : "clock.badge.questionmark")
        status.backgroundColor = pending ? .systemGreen : .systemOrange

        // Deliberately `.normal`, not `.destructive`: the destructive style plays a
        // row-removal animation on tap, which looks like the delete already happened
        // and tears the row down before the confirmation is answered.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { _, _, done in
            requestDelete(tx)
            done(false)   // the row stays until the alert is answered
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed

        return UISwipeActionsConfiguration(actions: [status, delete])
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
