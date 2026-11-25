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
}
