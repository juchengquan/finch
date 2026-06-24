import XCTest
import GRDB
@testable import FinchCore

final class RefundLinkTests: XCTestCase {
    private func addExpense(_ q: DatabaseQueue) throws -> String {
        try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-80),
            "merchant": .string("Store"), "categoryId": .string("c1"), "date": .string("2026-06-01")]))!
    }
    private func refundedEntryId(_ q: DatabaseQueue, _ eid: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [eid]) }
    }

    func test_refund_linkedByEntryId_stored() throws {
        let q = try TestSeed.base()
        let expense = try addExpense(q)   // entry id (applyReturningId returns the entry id)
        let refund = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(30),
            "merchant": .string("Store"), "categoryId": .string("c1"), "date": .string("2026-06-05"),
            "kind": .string("refund"), "refundedTransactionId": .string(expense)]))!
        XCTAssertEqual(try refundedEntryId(q, refund), expense)
    }

    func test_refund_linkedByPostingId_resolvesToEntry() throws {
        let q = try TestSeed.base()
        let expense = try addExpense(q)
        let postingId = try q.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order LIMIT 1", arguments: [expense]) }!
        let refund = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(30),
            "merchant": .string("Store"), "categoryId": .string("c1"), "date": .string("2026-06-05"),
            "kind": .string("refund"), "refundedTransactionId": .string(postingId)]))!
        XCTAssertEqual(try refundedEntryId(q, refund), expense)   // posting id normalized to entry id
    }
}
