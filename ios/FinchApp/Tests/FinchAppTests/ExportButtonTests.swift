import XCTest
import CryptoKit
@testable import FinchApp
import FinchCore

/// Task 11 — export produces a valid, parseable pack stamped `device = "ios"`.
final class ExportButtonTests: XCTestCase {
    @MainActor
    func test_buildPackProducesValidBytes() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))

        let exportedData = try await store.buildPack()
        let parsed = try Pack.parse(exportedData)
        XCTAssertEqual(parsed.manifest.packFormatVersion, "1")
        XCTAssertEqual(parsed.manifest.exportedFrom?.device, "ios")
    }

    /// Regression: a `.finch` export must bundle stored receipts so the pack is
    /// self-contained (was `attachmentFiles: []` — receipts were dropped).
    @MainActor
    func test_buildPackIncludesAttachments() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))

        // Attach a receipt to the first transaction (mirrors the in-app flow).
        let entryId = try XCTUnwrap(store.txns.first?.id, "fixture has no transactions to attach to")
        let bytes = Data("receipt-bytes".utf8)
        let rel = "attachments/\(entryId)/att-export-test.jpg"
        let abs = store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: abs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: abs)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try store.apply(.setEntryAttachment, Args([
            "entryId": .string(entryId), "kind": .string("image"), "relPath": .string(rel),
            "mimeType": .string("image/jpeg"), "byteSize": .double(Double(bytes.count)), "sha256": .string(sha)]))

        let parsed = try Pack.parse(try await store.buildPack())
        XCTAssertEqual(parsed.manifest.attachments.count, 1, "export must bundle the receipt")
        XCTAssertEqual(parsed.manifest.attachments.items.first?.relPath, rel)
        XCTAssertEqual(parsed.manifest.attachments.items.first?.sha256, sha)

        try? FileManager.default.removeItem(at: abs)   // tidy the shared attachments dir
    }
}
