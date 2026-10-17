import XCTest
@testable import FinchApp
import FinchCore

/// `FinchStore`'s undo offer around the engine's `TransactionUndo`: when it
/// exists, when it ends, and what happens to receipt files in between. The
/// engine's restore fidelity is FinchCore's `TransactionUndoTests`; this is the
/// app's half — the rules the banner leans on.
final class DeleteUndoTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: name, withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
    }

    @MainActor
    private func loaded() async throws -> FinchStore {
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: fixture("sample")))
        XCTAssertNil(store.deleteUndo)
        return store
    }

    /// A plain, single-leg transaction to delete.
    @MainActor
    private func plainTx(_ store: FinchStore, skip: Int = 0) throws -> Tx {
        let plain = store.txns.filter { ($0.accountLegCount ?? 1) == 1 && $0.transferGroupId == nil && $0.entryId != nil }
        return try XCTUnwrap(plain.dropFirst(skip).first)
    }

    /// Write a receipt file and its row, the way `AttachmentWriter` does.
    @MainActor
    private func attachReceipt(_ store: FinchStore, to tx: Tx) throws -> URL {
        let entryId = try XCTUnwrap(tx.entryId)
        let rel = "attachments/\(entryId)/att-undo.jpg"
        let url = store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jpeg".utf8).write(to: url)
        try store.apply(.setEntryAttachment, Args([
            "id": .string("att-undo"), "entryId": .string(entryId), "kind": .string("image"),
            "relPath": .string(rel), "mimeType": .string("image/jpeg"),
            "byteSize": .double(4), "sha256": .string("x")]))
        return url
    }

    @MainActor
    func test_delete_offersUndo_andUndoPutsItBack() async throws {
        let store = try await loaded()
        let before = store.txns
        let tx = try plainTx(store)
        try store.deleteTransaction(tx.id)
        XCTAssertFalse(store.txns.contains { $0.id == tx.id })
        let offer = try XCTUnwrap(store.deleteUndo, "the delete — and the reproject after it — leave an offer up")
        XCTAssertEqual(offer.count, 1)
        try store.undoDelete()
        XCTAssertNil(store.deleteUndo, "an offer is spent by using it")
        XCTAssertEqual(store.txns, before, "the projection is exactly what it was")
    }

    @MainActor
    func test_bulkDelete_isOneUndoForAll() async throws {
        let store = try await loaded()
        let before = store.txns
        let ids = Array(store.txns.prefix(6).map(\.id))
        XCTAssertEqual(store.deleteTransactions(ids), ids.count)
        XCTAssertEqual(store.deleteUndo?.count, ids.count)
        try store.undoDelete()
        XCTAssertEqual(store.txns, before)
    }

    /// The rule that stops an undo resurrecting stale state: any other write
    /// ends the offer.
    @MainActor
    func test_anyOtherWrite_expiresTheOffer() async throws {
        let store = try await loaded()
        try store.deleteTransaction(try plainTx(store).id)
        XCTAssertNotNil(store.deleteUndo)
        try store.apply(.setExchangeRate, Args([
            "date": .string("2026-07-22"), "currency": .string("EUR"), "rate": .double(1.08), "source": .string("test")]))
        XCTAssertNil(store.deleteUndo)
        XCTAssertThrowsError(try store.undoDelete()) { XCTAssertEqual(($0 as? I18nError)?.code, "error.undo.stale") }
    }

    /// A newer delete replaces the offer; only the latest can be undone.
    @MainActor
    func test_aSecondDelete_replacesTheOffer() async throws {
        let store = try await loaded()
        let first = try plainTx(store), second = try plainTx(store, skip: 1)
        try store.deleteTransaction(first.id)
        let firstOffer = store.deleteUndo?.id
        try store.deleteTransaction(second.id)
        XCTAssertNotEqual(store.deleteUndo?.id, firstOffer)
        try store.undoDelete()
        XCTAssertTrue(store.txns.contains { $0.id == second.id })
        XCTAssertFalse(store.txns.contains { $0.id == first.id })
    }

    /// Receipt files outlive the delete for exactly as long as the offer does.
    @MainActor
    func test_receiptFile_keptWhileUndoable_thenUnlinked() async throws {
        let store = try await loaded()
        let tx = try plainTx(store)
        let file = try attachReceipt(store, to: tx)
        try store.deleteTransaction(tx.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "kept while the delete can be undone")
        XCTAssertNotNil(UserDefaults.standard.stringArray(forKey: FinchStore.undoLeftoversKey),
                        "remembered, so a kill inside the window still cleans up")
        store.expireDeleteUndo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "gone once the offer ends")
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: FinchStore.undoLeftoversKey))
    }

    @MainActor
    func test_receiptFile_survivesAnUndo() async throws {
        let store = try await loaded()
        let tx = try plainTx(store)
        let file = try attachReceipt(store, to: tx)
        try store.deleteTransaction(tx.id)
        try store.undoDelete()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.attachments(for: tx.id).map(\.id), ["att-undo"], "the row is back under its own id")
        store.expireDeleteUndo()   // nothing pending — must not touch the restored file
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
