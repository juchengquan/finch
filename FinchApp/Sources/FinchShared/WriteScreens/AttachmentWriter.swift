import Foundation
import SwiftUI
import PhotosUI
import CryptoKit
import FinchCore

/// Writes a picked photo into the live attachments tree under an entry id and
/// records it via `setEntryAttachment`. Shared by Add + Edit (the in-app
/// counterpart to the Share Extension flow).
enum AttachmentWriter {

    /// What the user is told when a receipt picked in the Add sheet could not be
    /// stored. The transaction itself was saved, so it says how to recover.
    static var receiptNotAttachedMessage: String {
        String(localized: "The transaction was saved, but its receipt couldn't be attached. Open the transaction to add it again.")
    }

    /// Store a receipt for a transaction whose sheet has already closed. With no
    /// sheet left to show an error in, a failure goes to the app-wide alert
    /// (`dataError`). It was discarded with `try?`, so the receipt was lost unseen.
    @MainActor
    static func attachAfterClose(store: FinchStore, _ write: () async throws -> Void) async {
        do { try await write() } catch { store.dataError = receiptNotAttachedMessage }
    }
    /// Raised when the picker hands back no photo data, which Photos does for an
    /// iCloud photo it cannot download, among others. That returned quietly, so
    /// the sheet closed or stayed as if the receipt had been attached.
    static var photoUnavailable: I18nError {
        I18nError("error.attachment.photoUnavailable", [:],
                  "This photo couldn't be loaded. If it's stored in iCloud, wait for it to download and try again.")
    }

    @MainActor
    static func write(item: PhotosPickerItem, entryId: String, store: FinchStore) async throws {
        try write(photo: try await item.loadTransferable(type: Data.self), entryId: entryId, store: store)
    }

    /// The part of `write(item:)` after Photos has answered, so a test can hand
    /// it what the picker returned, `nil` included.
    @MainActor
    static func write(photo data: Data?, entryId: String, store: FinchStore) throws {
        guard let data else { throw photoUnavailable }
        let attId = "att-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = store.attachmentsRoot.appendingPathComponent(entryId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rel = "attachments/\(entryId)/\(attId).jpg"
        try data.write(to: store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try store.apply(.setEntryAttachment, Args([
            "entryId": .string(entryId), "kind": .string("image"), "relPath": .string(rel),
            "mimeType": .string("image/jpeg"), "byteSize": .double(Double(data.count)), "sha256": .string(sha)]))
    }

    /// macOS/file-picker counterpart of `write(item:)` — copies a picked file
    /// (image or PDF) into the attachments tree and records it.
    @MainActor
    static func writeFile(url: URL, entryId: String, store: FinchStore) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let (kind, mime): (String, String) =
            ext == "pdf"  ? ("pdf", "application/pdf") :
            ext == "png"  ? ("image", "image/png") :
                            ("image", "image/jpeg")
        let attId = "att-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = store.attachmentsRoot.appendingPathComponent(entryId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeExt = ext.isEmpty ? "dat" : ext
        let rel = "attachments/\(entryId)/\(attId).\(safeExt)"
        try data.write(to: store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try store.apply(.setEntryAttachment, Args([
            "entryId": .string(entryId), "kind": .string(kind), "relPath": .string(rel),
            "mimeType": .string(mime), "byteSize": .double(Double(data.count)), "sha256": .string(sha)]))
    }
}
