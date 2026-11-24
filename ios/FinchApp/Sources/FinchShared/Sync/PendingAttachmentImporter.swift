import Foundation
import FinchCore

/// Phase 6.5 — imports receipts the Share Extension staged into the App Group.
/// For each pending manifest: move the file into the live attachments tree,
/// create a pending placeholder transaction, dispatch setEntryAttachment, and
/// delete the manifest. The user then edits the new transaction's amount.
@MainActor
public enum PendingAttachmentImporter {
    /// The live attachments directory (next to the DB), where the pack reads from.
    static var attachmentsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("attachments", isDirectory: true)
    }

    /// Returns the number of receipts imported.
    @discardableResult
    public static func importPending(into store: FinchStore) -> Int {
        let fm = FileManager.default
        guard let manifests = try? fm.contentsOfDirectory(at: AppGroup.pendingManifestsDir,
                                                          includingPropertiesForKeys: nil),
              !store.ledgers.isEmpty, let account = store.accounts.first else { return 0 }
        var imported = 0
        for mURL in manifests where mURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: mURL),
                  let m = try? JSONDecoder().decode(PendingAttachment.self, from: data) else { continue }
            do {
                // 1. placeholder pending transaction (user fills in the amount later).
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

                // 2. move the staged file into attachments/<entryId>/<id>.<ext> — the folder `AttachmentWriter` uses.
                let ext = (m.relPath as NSString).pathExtension
                let destDir = attachmentsRoot.appendingPathComponent(entryId, isDirectory: true)
                try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                let rel = "attachments/\(entryId)/\(m.id).\(ext)"
                let dest = attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel)
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: AppGroup.containerURL.appendingPathComponent(m.relPath), to: dest)

                // 3. record the attachment row.
                try store.apply(.setEntryAttachment, Args([
                    "entryId": .string(entryId), "kind": .string(m.kind), "relPath": .string(rel),
                    "mimeType": .string(m.mimeType), "byteSize": .double(Double(m.byteSize)),
                    "sha256": .string(m.sha256),
                    "originalFilename": m.originalFilename.map { JSONValue.string($0) } ?? .null]))
                try? fm.removeItem(at: mURL)
                imported += 1
            } catch { continue }
        }
        return imported
    }

    private static func today() -> String { AppDate.today() }
}
