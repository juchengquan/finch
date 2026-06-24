import XCTest
import GRDB
@testable import FinchCore

final class TransferTagsStatusTests: XCTestCase {
    private func seededWithA2() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("cash"), "currency": .string("USD")]))
        return q
    }
    private func transferEntryId(_ q: DatabaseQueue) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM entries WHERE kind='transfer' LIMIT 1") }
    }

    func test_createTransfer_withStatusAndTags() throws {
        let q = try seededWithA2()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("Trip")]))
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"), "fromAmount": .double(50),
            "date": .string("2026-06-01"), "status": .string("pending"), "tagIds": .array([.string("t1")])]))
        let eid = try transferEntryId(q)!
        let status = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id=?", arguments: [eid]) }
        let tagCount = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags WHERE entry_id=? AND tag_id='t1'", arguments: [eid]) }
        XCTAssertEqual(status, "pending")
        XCTAssertEqual(tagCount, 1)
    }

    func test_createTransfer_defaultsUnchanged() throws {
        let q = try seededWithA2()
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"), "fromAmount": .double(50), "date": .string("2026-06-01")]))
        let eid = try transferEntryId(q)!
        let status = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id=?", arguments: [eid]) }
        let tagCount = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags WHERE entry_id=?", arguments: [eid]) }
        XCTAssertEqual(status, "confirmed")
        XCTAssertEqual(tagCount, 0)
    }
}
