import XCTest
@testable import FinchApp
import FinchCore

/// The shared bulk-delete check both feeds' confirmations use.
final class BulkDeleteTests: XCTestCase {
    private func tx(_ id: String, entry: String, group: String? = nil) -> Tx {
        Tx(id: id, merchant: "m", amount: -1, account: "a", date: "2026-05-01", entryId: entry, groupId: group)
    }

    func test_oneLegOfASplitTender_takesItsSibling() {
        let txns = [tx("p1", entry: "e1"), tx("p2", entry: "e1"), tx("p3", entry: "e2")]
        XCTAssertTrue(BulkDelete.takesUnselectedRows(["p1"], in: txns))
        XCTAssertFalse(BulkDelete.takesUnselectedRows(["p1", "p2"], in: txns), "both legs ticked — nothing unseen goes")
        XCTAssertFalse(BulkDelete.takesUnselectedRows(["p3"], in: txns))
    }

    /// A grid member is its own entry; its group-mates survive the delete, so
    /// they are no reason to warn.
    func test_gridSiblings_doNotWarn() {
        let txns = [tx("p1", entry: "e1", group: "g"), tx("p2", entry: "e2", group: "g")]
        XCTAssertFalse(BulkDelete.takesUnselectedRows(["p1"], in: txns))
    }

    func test_title_countsWhatWasTicked() {
        XCTAssertTrue(BulkDelete.confirmTitle(3).contains("3"))
    }
}
