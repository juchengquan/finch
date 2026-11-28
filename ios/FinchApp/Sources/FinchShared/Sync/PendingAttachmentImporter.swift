import Foundation
import FinchCore

/// Phase 6.5 — imports receipts the Share Extension staged into the App Group.
/// For each pending manifest: convert the file to its stored shape, create a
/// pending placeholder transaction, write the file into the live attachments
/// tree with setEntryAttachment, and delete the staged copy and the manifest.
/// The user then edits the new transaction's amount.
@MainActor
public enum PendingAttachmentImporter {
    /// Shown when a shared receipt can't be read. It used to be imported anyway,
    /// as whatever bytes the extension staged under an `image/jpeg` label.
    static var sharedUnreadable: I18nError {
        I18nError("error.attachment.sharedUnreadable", [:],
                  "A receipt shared to finch couldn't be read, so it wasn't added.")
    }

    /// Returns the number of receipts imported.
    @discardableResult
    public static func importPending(into store: FinchStore) async -> Int {
        let fm = FileManager.default
        guard let manifests = try? fm.contentsOfDirectory(at: AppGroup.pendingManifestsDir,
                                                          includingPropertiesForKeys: nil),
              !store.ledgers.isEmpty, let account = store.accounts.first else { return 0 }
        var imported = 0, unreadable = 0
        // In a fixed order: the directory lists them in whatever order the file
        // system keeps.
        for mURL in manifests.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where mURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: mURL),
                  let m = try? JSONDecoder().decode(PendingAttachment.self, from: data) else { continue }
            let staged = AppGroup.containerURL.appendingPathComponent(m.relPath)

            // 1. the receipt in its stored shape (`AttachmentWriter.stored`), worked
            // out before anything is created. The extension stages what the sharing
            // app handed it, often a HEIC; this is where it becomes an upright JPEG
            // with no metadata, as a receipt added in the app does. One that can't be
            // read is reported and dropped rather than imported as a broken file.
            guard let bytes = try? Data(contentsOf: staged),
                  let receipt = try? await AttachmentWriter.storedOffMain(bytes) else {
                unreadable += 1
                try? fm.removeItem(at: staged)
                try? fm.removeItem(at: mURL)
                continue
            }
            do {
                // 2. placeholder pending transaction (user fills in the amount later).
                let merchant = m.originalFilename.map { ($0 as NSString).deletingPathExtension } ?? "Receipt"
                // The engine says which entry it made. Finding it by comparing the
                // list before and after went wrong at launch, where this runs: the
                // list is still loading, so "before" was empty and the first row of
                // the reloaded list — any newer transaction — took the receipt.
                guard let entryId = try store.applyReturningId(.addTransaction, Args([
                    "ledgerId": .string(store.activeLedgerId), "accountId": .string(account.id),
                    "amount": .double(0), "merchant": .string(merchant),
                    "categoryId": .string(store.pickableCategories.first?.id ?? ""),
                    "date": .string(Self.today()), "status": .string("pending"), "skipRules": .bool(true)]))
                else { continue }

                // 3. write it to attachments/<entryId>/<id>.<ext> — the folder
                // `AttachmentWriter` uses — and record the row.
                try AttachmentWriter.record(receipt, entryId: entryId, store: store,
                                            originalFilename: m.originalFilename, id: m.id)
                try? fm.removeItem(at: staged)
                try? fm.removeItem(at: mURL)
                imported += 1
            } catch { continue }
        }
        // Reported once every receipt is in. Each import is a write, and a write's
        // reprojection clears `dataError`, so an alert set mid-loop was wiped by the
        // next receipt that imported cleanly.
        if unreadable > 0 { store.dataError = i18nMessage(sharedUnreadable) }
        return imported
    }

    private static func today() -> String { AppDate.today() }
}
