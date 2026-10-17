import Foundation
import FinchCore
import GRDB
#if canImport(UIKit)
import UIKit
#endif

/// An offer to undo the most recent transaction delete — what the app-wide Undo
/// banner shows. Holds the engine's snapshot of everything the delete took.
public struct DeleteUndo: Identifiable, Equatable {
    public let id = UUID()
    /// How many transactions the user deleted — what the banner counts.
    public let count: Int
    let snapshot: DeletedTransactions

    /// The banner's text. Counts what the user deleted (rows ticked, or the one
    /// row), not entries — the two differ for a split purchase.
    public var message: String {
        count == 1 ? String(localized: "Transaction deleted")
                   : String(localized: "\(count) transactions deleted")
    }
}

/// Undo after delete.
///
/// **What comes back:** everything `TransactionUndo` captures — the entry with all
/// its legs, splits, tags and receipt rows, both halves of a cross-ledger
/// transfer, the refund links and grid membership the delete cleared on rows
/// nobody selected — under the original ids.
///
/// **When the offer ends** (`expireDeleteUndo`): after `undoWindow`; on ANY other
/// write through the chokepoint, including a new delete (which offers its own);
/// when a pack import replaces the database; and when the app goes to the
/// background. Expiring on every write is the rule that keeps an undo from
/// resurrecting stale state: the snapshot is only "the ledger before the delete"
/// while nothing else has changed it. The engine refuses a stale restore on its
/// own as a backstop, but the app never lets one get that far. The reprojection
/// that follows the delete is not a write in this sense — it goes around `apply`
/// — so the offer survives it.
///
/// **Receipt files:** the engine is filesystem-agnostic, so the delete only drops
/// the attachment ROWS. The files used to be unlinked immediately; now they stay
/// until the offer ends, then go unless a restore put their rows back. The
/// pending paths are also written to UserDefaults, so a kill inside the window
/// leaves nothing behind: the next launch sweeps them.
extension FinchStore {
    /// How long the offer stays up. Longer under VoiceOver, where reaching the
    /// button takes several gestures after the announcement.
    static var undoWindow: Duration {
        #if canImport(UIKit) && !os(watchOS)
        if UIAccessibility.isVoiceOverRunning { return .seconds(12) }
        #endif
        return .seconds(5)
    }

    static let undoLeftoversKey = "finch.undo.pendingUnlink"

    /// Snapshot what deleting `ids` will take. Nil only on a read failure, in which
    /// case the delete still happens — it just can't be undone.
    func captureForUndo(_ ids: [String]) -> DeletedTransactions? {
        guard let q = dbQueue else { return nil }
        return try? q.read { try TransactionUndo.capture($0, txIds: ids) }
    }

    /// Call right after the delete: narrow the capture to what actually went and
    /// put the offer up. The delete's own write has already expired the previous
    /// offer, so there is only ever one.
    func offerUndo(_ captured: DeletedTransactions?, count: Int) {
        guard let q = dbQueue, let captured,
              let settled = try? q.read({ try TransactionUndo.settle(captured, $0) }),
              !settled.isEmpty else { return }
        let files = settled.attachmentRelPaths
        if !files.isEmpty { UserDefaults.standard.set(files, forKey: Self.undoLeftoversKey) }
        deleteUndo = DeleteUndo(count: count, snapshot: settled)
        let offer = deleteUndo?.id
        deleteUndoExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled, let self, self.deleteUndo?.id == offer else { return }
            self.expireDeleteUndo()
        }
    }

    /// Put the deleted transactions back. Throws when there is nothing to undo or
    /// the engine refuses (the ledger changed underneath); either way the offer
    /// is gone afterwards.
    public func undoDelete() throws {
        guard let offer = deleteUndo else {
            throw I18nError("error.undo.stale", [:], "This can't be undone any more — the ledger changed since the delete.")
        }
        do {
            // Through the chokepoint like every write — its side effects end the
            // offer, and by then the receipt rows are back, so the files stay.
            try apply(.restoreTransactions, try offer.snapshot.args)
        } catch {
            expireDeleteUndo()
            throw error
        }
    }

    /// End the offer and drop the receipt files nothing references any more.
    public func expireDeleteUndo() {
        deleteUndoExpiry?.cancel()
        deleteUndoExpiry = nil
        guard let offer = deleteUndo else { return }
        deleteUndo = nil
        unlinkUnreferenced(offer.snapshot.attachmentRelPaths)
        UserDefaults.standard.removeObject(forKey: Self.undoLeftoversKey)
    }

    /// Launch: finish an expiry a kill interrupted.
    func sweepUndoLeftovers() {
        guard let paths = UserDefaults.standard.stringArray(forKey: Self.undoLeftoversKey) else { return }
        unlinkUnreferenced(paths)
        UserDefaults.standard.removeObject(forKey: Self.undoLeftoversKey)
    }

    /// Unlink each path no attachment row still names — a restored one does,
    /// and so would any other row sharing the file.
    private func unlinkUnreferenced(_ relPaths: [String]) {
        guard !relPaths.isEmpty, let q = dbQueue else { return }
        let referenced = (try? q.read { db in
            try String.fetchAll(db, sql: "SELECT rel_path FROM entry_attachments WHERE rel_path IN (\(relPaths.map { _ in "?" }.joined(separator: ",")))",
                                arguments: StatementArguments(relPaths))
        }).map(Set.init) ?? Set(relPaths)   // can't tell → keep them all
        unlink(relPaths: relPaths.filter { !referenced.contains($0) })
    }
}
