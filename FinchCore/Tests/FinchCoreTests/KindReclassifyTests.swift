import XCTest
import GRDB
@testable import FinchCore

final class KindReclassifyTests: XCTestCase {
    private func addExpense(_ q: DatabaseQueue) throws -> String {
        try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
            "skipRules": .bool(true)]))!
    }
    private func kind(_ q: DatabaseQueue, _ id: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT kind FROM entries WHERE id = ?", arguments: [id]) }
    }
    private func acctAmount(_ q: DatabaseQueue, _ id: String) throws -> Double? {
        try q.read { db in try Double.fetchOne(db, sql: "SELECT amount FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [id]) }
    }
    private func update(_ q: DatabaseQueue, _ id: String, _ patch: [String: JSONValue]) throws {
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args(["id": .string(id), "patch": .object(patch)]))
    }

    func test_expense_to_income_resigns_positive() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        try update(q, id, ["kind": .string("income"), "amount": .double(25)])
        XCTAssertEqual(try kind(q, id), "income")
        XCTAssertEqual(try acctAmount(q, id) ?? 0, 25, accuracy: 0.001)   // positive account leg
    }

    func test_expense_to_refund_positive() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        try update(q, id, ["kind": .string("refund"), "amount": .double(25)])
        XCTAssertEqual(try kind(q, id), "refund")
        XCTAssertGreaterThan(try acctAmount(q, id) ?? 0, 0)
    }

    func test_refund_rejects_negative_amount() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        XCTAssertThrowsError(try update(q, id, ["kind": .string("refund"), "amount": .double(-25)]))   // refund needs > 0
    }

    func test_refund_to_expense_resigns_negative_and_clears_link() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        try update(q, id, ["kind": .string("refund"), "amount": .double(25)])
        try update(q, id, ["kind": .string("expense"), "amount": .double(-25), "refundedTransactionId": .null])
        XCTAssertEqual(try kind(q, id), "expense")
        XCTAssertEqual(try acctAmount(q, id) ?? 0, -25, accuracy: 0.001)   // negative account leg
        let link = try q.read { db in try String.fetchOne(db, sql: "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [id]) }
        XCTAssertNil(link)
    }
}
