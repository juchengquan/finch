import XCTest
import FinchCore
import GRDB
import ImageIO
import UniformTypeIdentifiers
@testable import FinchApp

/// A receipt shared into finch is imported at launch, onto a new pending
/// transaction. It found that transaction by diffing the list before and after —
/// and at launch the list is still loading, so "before" was empty and the newest
/// row of the reloaded list took the receipt instead.
@MainActor
final class SharedReceiptImportTests: XCTestCase {
    func test_aReceiptImportedAtLaunchAttachesToItsOwnTransaction() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        // A row dated after today sits at the top of the list — where the set-diff looked.
        let account = try XCTUnwrap(store.accounts.first)
        try store.apply(.addTransaction, Args([
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(account.id), "amount": .double(-900),
            "merchant": .string("Rent next year"), "date": .string("2099-01-01"), "skipRules": .bool(true)]))
        // Launch: the list is projected on a background task and is empty until it lands.
        store.isHydrating = true
        store.reprojectActiveLedger()
        store.isHydrating = false
        XCTAssertTrue(store.txns.isEmpty, "the premise: the list is still loading")

        // Stage one receipt the way the Share Extension does.
        let fm = FileManager.default
        let tag = UUID().uuidString.prefix(8)
        try fm.createDirectory(at: AppGroup.pendingManifestsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: AppGroup.pendingFilesDir, withIntermediateDirectories: true)
        let rel = "pending_attachments/files/\(tag).pdf"
        try Data("%PDF-1.4".utf8).write(to: AppGroup.containerURL.appendingPathComponent(rel))
        let sha = "test-\(tag)"
        let manifest = PendingAttachment(id: "att-\(tag)", kind: "pdf", relPath: rel, mimeType: "application/pdf",
                                         byteSize: 8, sha256: sha, originalFilename: "Invoice \(tag).pdf")
        let mURL = AppGroup.pendingManifestsDir.appendingPathComponent("\(tag).json")
        try JSONEncoder().encode(manifest).write(to: mURL)
        defer { try? fm.removeItem(at: mURL) }

        await PendingAttachmentImporter.importPending(into: store)

        // Found by its file name: the importer hashes the bytes it stores.
        let q = try XCTUnwrap(store.dbQueue)
        let owner = try await q.read { db in
            try String.fetchOne(db, sql: """
                SELECT e.description FROM entry_attachments a JOIN entries e ON e.id = a.entry_id
                 WHERE a.original_filename = ?
                """, arguments: ["Invoice \(tag).pdf"])
        }
        XCTAssertEqual(owner, "Invoice \(tag)", "not the transaction that happened to be newest")
    }

    /// The extension stages what the sharing app handed it, under an
    /// `image/jpeg` label whatever it was. The importer stores it as the JPEG
    /// the label claims; one it can't read is reported, not imported as a
    /// broken file.
    func test_aSharedImageIsStoredAsAJPEGAndAnUnreadableOneIsReported() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let fm = FileManager.default
        try fm.createDirectory(at: AppGroup.pendingManifestsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: AppGroup.pendingFilesDir, withIntermediateDirectories: true)

        func stage(_ bytes: Data, name: String) throws -> (tag: String, manifest: URL, file: URL) {
            let tag = String(UUID().uuidString.prefix(8))
            let rel = "pending_attachments/files/\(tag).jpg"
            let file = AppGroup.containerURL.appendingPathComponent(rel)
            try bytes.write(to: file)
            let m = PendingAttachment(id: "att-\(tag)", kind: "image", relPath: rel, mimeType: "image/jpeg",
                                      byteSize: bytes.count, sha256: "staged", originalFilename: "\(name) \(tag).jpg")
            let mURL = AppGroup.pendingManifestsDir.appendingPathComponent("\(tag).json")
            try JSONEncoder().encode(m).write(to: mURL)
            return (tag, mURL, file)
        }
        let png = try XCTUnwrap(try ReceiptFileTypeTests.encode(.png, properties: [:]))
        let good = try stage(png, name: "Lunch")
        let bad = try stage(Data("not an image".utf8), name: "Broken")
        defer { for u in [good.manifest, good.file, bad.manifest, bad.file] { try? fm.removeItem(at: u) } }

        await PendingAttachmentImporter.importPending(into: store)

        let q = try XCTUnwrap(store.dbQueue)
        let rows = try await q.read { db in
            try Row.fetchAll(db, sql: "SELECT original_filename, mime_type, rel_path FROM entry_attachments WHERE original_filename IN (?, ?)",
                             arguments: ["Lunch \(good.tag).jpg", "Broken \(bad.tag).jpg"])
        }
        XCTAssertEqual(rows.count, 1, "only the readable one was imported")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row["mime_type"] as String?, "image/jpeg")
        let stored = try Data(contentsOf: store.attachmentsRoot.deletingLastPathComponent()
            .appendingPathComponent(row["rel_path"] as String))
        let type = CGImageSourceCreateWithData(stored as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
        XCTAssertEqual(type, UTType.jpeg.identifier, "a JPEG, not the PNG that was shared")

        XCTAssertEqual(store.dataError, i18nMessage(PendingAttachmentImporter.sharedUnreadable))
        XCTAssertFalse(fm.fileExists(atPath: bad.manifest.path), "and it isn't retried at every launch")
        XCTAssertFalse(fm.fileExists(atPath: good.manifest.path))
    }

    /// The launch projection lands after a write made while it ran. It used to
    /// publish anyway, replacing the newer rows: the write vanished from the list.
    func test_aLateLaunchProjectionDoesNotReplaceNewerRows() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let account = try XCTUnwrap(store.accounts.first)
        store.isHydrating = true
        store.reprojectActiveLedger()          // the launch projection starts in the background
        store.isHydrating = false
        try store.apply(.addTransaction, Args([  // a write lands before it finishes
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(account.id), "amount": .double(-12),
            "merchant": .string("Written during launch"), "date": .string(store.wallToday), "skipRules": .bool(true)]))
        XCTAssertTrue(store.txns.contains { $0.merchant == "Written during launch" })
        await store.awaitTxnsReady()
        // Let the background projection finish and try to publish.
        for _ in 0..<50 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(store.txns.contains { $0.merchant == "Written during launch" },
                      "the stale launch projection must not replace the newer rows")
    }
}
