import Foundation
import SwiftUI
import PhotosUI
import CryptoKit
import FinchCore

/// Writes a picked photo into the live attachments tree under an entry id and
/// records it via `setEntryAttachment`. Shared by Add + Edit (the in-app
/// counterpart to the Share Extension flow).
enum AttachmentWriter {
    @MainActor
    static func write(item: PhotosPickerItem, entryId: String, store: FinchStore) async throws {
        guard let data = try await item.loadTransferable(type: Data.self) else { return }
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
}
