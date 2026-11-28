import Foundation
import SwiftUI
import PhotosUI
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import FinchCore

/// Writes a picked photo into the live attachments tree under an entry id and
/// records it via `setEntryAttachment`. Shared by Add + Edit (the in-app
/// counterpart to the Share Extension flow).
///
/// Every receipt is stored in the shape the web's `processBytes`
/// (`lib/attachments/process.ts`) gives it: an image becomes an upright JPEG
/// with no metadata, and a PDF is kept as it is. See `stored(_:)`.
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

    /// Raised when the bytes are neither a PDF nor an image ImageIO can decode.
    static var unreadable: I18nError {
        I18nError("error.attachment.unreadable", [:], "This file isn't a photo or PDF that finch can read.")
    }

    // MARK: The stored shape

    /// A receipt as it is written to disk and recorded.
    struct StoredReceipt: Sendable {
        let bytes: Data
        let kind: String   // entry_attachments.kind
        let mime: String
        let ext: String
    }

    /// JPEG quality, the web's `sharp(...).jpeg({ quality: 88 })`.
    static let jpegQuality = 0.88

    /// The bytes in their stored shape, judged by what they contain rather than
    /// a file name or what the picker claims.
    ///
    /// - A PDF is kept as it is.
    /// - An image (HEIC, JPEG, PNG, …) is re-encoded as a JPEG, turned upright by
    ///   its orientation tag, with its metadata left behind: no location, no
    ///   camera details. That is the web's choice (RECEIPT_PHOTOS_PLAN §0, 1b):
    ///   a JPEG opens everywhere, where a HEIC does not open in Chrome or
    ///   Firefox.
    ///
    /// Before this, a photo was stored exactly as Photos handed it over (usually
    /// HEIC, with its location) under a `.jpg` name and an `image/jpeg` label.
    ///
    /// Decoding a full-size photo is slow, so callers run this off the main actor.
    static func stored(_ data: Data) throws -> StoredReceipt {
        if isPDF(data) { return StoredReceipt(bytes: data, kind: "pdf", mime: "application/pdf", ext: "pdf") }
        guard let jpeg = uprightJPEG(data) else { throw unreadable }
        return StoredReceipt(bytes: jpeg, kind: "image", mime: "image/jpeg", ext: "jpg")
    }

    /// A PDF's header, which may sit anywhere in the first 1024 bytes.
    static func isPDF(_ data: Data) -> Bool {
        data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil
    }

    /// The image re-encoded as a JPEG at full size, upright, with no metadata.
    /// `nil` when ImageIO can't decode it.
    static func uprightJPEG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // A "thumbnail" as large as the image is ImageIO's way of applying the
        // orientation tag to the pixels; the image itself is decoded as stored.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // Only the pixels go in: none of the source's properties are copied, so
        // its EXIF, GPS and maker data stay behind.
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// `stored(_:)` on a background thread.
    static func storedOffMain(_ data: Data) async throws -> StoredReceipt {
        try await Task.detached(priority: .userInitiated) { try stored(data) }.value
    }

    // MARK: Writers

    @MainActor
    static func write(item: PhotosPickerItem, entryId: String, store: FinchStore) async throws {
        try await write(photo: try await item.loadTransferable(type: Data.self), entryId: entryId, store: store)
    }

    /// The part of `write(item:)` after Photos has answered, so a test can hand
    /// it what the picker returned, `nil` included.
    @MainActor
    static func write(photo data: Data?, entryId: String, store: FinchStore) async throws {
        guard let data else { throw photoUnavailable }
        try record(try await storedOffMain(data), entryId: entryId, store: store)
    }

    /// macOS/file-picker counterpart of `write(item:)` — copies a picked file
    /// (image or PDF) into the attachments tree and records it.
    @MainActor
    static func writeFile(url: URL, entryId: String, store: FinchStore) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        try record(try await storedOffMain(data), entryId: entryId, store: store)
    }

    /// Write a stored receipt under `attachments/<entryId>/` and record its row.
    @MainActor
    static func record(_ receipt: StoredReceipt, entryId: String, store: FinchStore,
                       originalFilename: String? = nil, id: String? = nil) throws {
        let attId = id ?? "att-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = store.attachmentsRoot.appendingPathComponent(entryId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rel = "attachments/\(entryId)/\(attId).\(receipt.ext)"
        try receipt.bytes.write(to: store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel))
        let sha = SHA256.hash(data: receipt.bytes).map { String(format: "%02x", $0) }.joined()
        var args: [String: JSONValue] = [
            "entryId": .string(entryId), "kind": .string(receipt.kind), "relPath": .string(rel),
            "mimeType": .string(receipt.mime), "byteSize": .double(Double(receipt.bytes.count)), "sha256": .string(sha)]
        if let originalFilename { args["originalFilename"] = .string(originalFilename) }
        try store.apply(.setEntryAttachment, Args(args))
    }
}
