import XCTest
import GRDB
@testable import FinchCore

final class AddTransactionFieldsTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue { try TestSeed.base() }   // l1 / a1 / c1

    private func addArgs(_ extra: [String: JSONValue] = [:]) -> Args {
        var d: [String: JSONValue] = [
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-12),
            "merchant": .string("Lunch"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
        ]
        for (k, v) in extra { d[k] = v }
        return Args(d)
    }

    func test_addTransaction_writesTags() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("Work")]))
        let eid = try q.write { db in try Transactions.addTransactionReturningId(db, addArgs(["tagIds": .array([.string("t1")])])) }
        let n = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags WHERE entry_id = ? AND tag_id = ?", arguments: [eid, "t1"]) }
        XCTAssertEqual(n, 1)
    }

    func test_addTransaction_statusPendingAndDefault() throws {
        let q = try seeded()
        let pendingId = try q.write { db in try Transactions.addTransactionReturningId(db, addArgs(["status": .string("pending")])) }
        let defaultId = try q.write { db in try Transactions.addTransactionReturningId(db, addArgs()) }
        let pStatus = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id = ?", arguments: [pendingId]) }
        let dStatus = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id = ?", arguments: [defaultId]) }
        XCTAssertEqual(pStatus, "pending")
        XCTAssertEqual(dStatus, "confirmed")
    }

    func test_applyReturningId_addTransactionReturnsId_otherNil() throws {
        let q = try seeded()
        let id = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: addArgs())
        XCTAssertNotNil(id)
        let exists = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE id = ?", arguments: [id!]) }
        XCTAssertEqual(exists, 1)
        let none = try Apply.applyReturningId(dbQueue: q, action: "createTag", args: Args(["id": .string("t2"), "ledgerId": .string("l1"), "name": .string("X")]))
        XCTAssertNil(none)
    }
}
