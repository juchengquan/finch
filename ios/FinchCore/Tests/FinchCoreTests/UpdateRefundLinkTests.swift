import XCTest
import GRDB
@testable import FinchCore

final class UpdateRefundLinkTests: XCTestCase {
    private func add(_ q: DatabaseQueue, _ amount: Double) throws -> String {
        try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amount),
            "merchant": .string("M"), "categoryId": .string("c1"), "date": .string("2026-06-01")]))!
    }

    func test_updateTransaction_resolvesRefundLinkPostingIdToEntry() throws {
        let q = try TestSeed.base()
        let e1 = try add(q, -80)          // the original purchase (entry id)
        let e2 = try add(q, 30)           // the row we attach the link to (entry id)
        let posting = try q.read { db in try String.fetchOne(db, sql:
            "SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order LIMIT 1",
            arguments: [e1]) }!
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(e2), "patch": .object(["refundedTransactionId": .string(posting)])]))
        let ref = try q.read { db in try String.fetchOne(db, sql:
            "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [e2]) }
        XCTAssertEqual(ref, e1)           // posting id normalized to the entry id

        // Clearing still works (null → null).
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(e2), "patch": .object(["refundedTransactionId": .null])]))
        let cleared = try q.read { db in try String.fetchOne(db, sql:
            "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [e2]) }
        XCTAssertNil(cleared)
    }
}
