import XCTest
import FinchCore
@testable import FinchApp

/// A receipt picked in the Add sheet is written after the sheet closes. A failure
/// there was dropped with `try?`, so the receipt was lost without a word.
@MainActor
final class ReceiptAfterCloseTests: XCTestCase {

    func test_aFailedReceiptWriteIsReported() async {
        let store = FinchStore()
        struct DiskFull: Error {}
        await AttachmentWriter.attachAfterClose(store: store) { throw DiskFull() }
        XCTAssertEqual(store.dataError, AttachmentWriter.receiptNotAttachedMessage)

        let quiet = FinchStore()
        await AttachmentWriter.attachAfterClose(store: quiet) {}
        XCTAssertNil(quiet.dataError, "a write that lands says nothing")
    }

    /// Photos can answer a pick with no data (an iCloud photo it cannot
    /// download). That returned quietly: no receipt, and no word about it.
    func test_aPhotoWithNoDataIsReported() async {
        let store = FinchStore()
        do {
            try await AttachmentWriter.write(photo: nil, entryId: "e1", store: store)
            XCTFail("a pick with no data must throw")
        } catch {
            XCTAssertEqual((error as? I18nError)?.code, "error.attachment.photoUnavailable")
        }

        // After the Add sheet has closed, it reaches the app-wide alert.
        await AttachmentWriter.attachAfterClose(store: store) {
            try await AttachmentWriter.write(photo: nil, entryId: "e1", store: store)
        }
        XCTAssertEqual(store.dataError, AttachmentWriter.receiptNotAttachedMessage)
    }

    /// And it reads in Chinese on a Chinese phone.
    func test_thePhotoErrorHasChinese() {
        let zh = i18nMessage(AttachmentWriter.photoUnavailable, zh: true)
        XCTAssertNotEqual(zh, AttachmentWriter.photoUnavailable.message)
        XCTAssertTrue(zh.contains("iCloud"), zh)
    }
}
