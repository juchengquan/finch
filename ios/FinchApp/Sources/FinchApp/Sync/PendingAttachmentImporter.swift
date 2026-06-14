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
                // Snapshot existing ids so we can identify the new row by set-diff —
                // matching on merchant name attaches to the wrong tx when two
                // receipts derive the same name (e.g. two "Receipt.jpg").
                let before = Set(store.txns.map { $0.id })
                try store.apply(.addTransaction, Args([
                    "ledgerId": .string(store.activeLedgerId), "accountId": .string(account.id),
                    "amount": .double(0), "merchant": .string(merchant),
                    "categoryId": .string(store.pickableCategories.first?.id ?? ""),
                    "date": .string(Self.today()), "status": .string("pending"), "skipRules": .bool(true)]))
                // The new tx id (an account-posting id); setEntryAttachment resolves
                // it to the entry. Use it for the attachment path too.
                guard let txId = store.txns.first(where: { !before.contains($0.id) })?.id else { continue }

                // 2. move the staged file into attachments/<txId>/<id>.<ext>.
                let ext = (m.relPath as NSString).pathExtension
                let destDir = attachmentsRoot.appendingPathComponent(txId, isDirectory: true)
                try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                let rel = "attachments/\(txId)/\(m.id).\(ext)"
                let dest = attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel)
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: AppGroup.containerURL.appendingPathComponent(m.relPath), to: dest)

                // 3. record the attachment row.
                try store.apply(.setEntryAttachment, Args([
                    "entryId": .string(txId), "kind": .string(m.kind), "relPath": .string(rel),
                    "mimeType": .string(m.mimeType), "byteSize": .double(Double(m.byteSize)),
                    "sha256": .string(m.sha256),
                    "originalFilename": m.originalFilename.map { JSONValue.string($0) } ?? .null]))
                try? fm.removeItem(at: mURL)
                imported += 1
            } catch { continue }
        }
        return imported
    }

    private static func today() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
