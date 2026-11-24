import XCTest
import FinchCore
import GRDB
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

        PendingAttachmentImporter.importPending(into: store)

        let q = try XCTUnwrap(store.dbQueue)
        let owner = try await q.read { db in
            try String.fetchOne(db, sql: """
                SELECT e.description FROM entry_attachments a JOIN entries e ON e.id = a.entry_id WHERE a.sha256 = ?
                """, arguments: [sha])
        }
        XCTAssertEqual(owner, "Invoice \(tag)", "not the transaction that happened to be newest")
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
