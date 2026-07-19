import XCTest
import GRDB
@testable import FinchCore

/// Tag merge repoints the entry_tags join (dedup on the composite PK), repoints
/// rule actions, and deletes the source tag(s). iOS-only — no web parity.
final class TagMergeTests: XCTestCase {
    private func freshDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        return q
    }

    /// Seed a ledger, an account, two tags (t1, t2), and a category.
    private func seed(_ q: DatabaseQueue) throws {
        try Apply.apply(dbQueue: q, action: "createLedger", args: Args([
            "id": .string("l1"), "name": .string("L"), "base": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "ledgerId": .string("l1"), "id": .string("a1"), "name": .string("A"), "type": .string("cash"), "currency": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("Food")]))
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t2"), "ledgerId": .string("l1"), "name": .string("food")]))
    }

    /// Add a transaction with the given tag ids.
    private func addTx(_ q: DatabaseQueue, id: String, tags: [String]) throws {
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string(id), "date": .string("2026-05-01"), "skipRules": .bool(true),
            "tagIds": .array(tags.map { .string($0) })]))
        XCTAssertNotNil(eid)
    }

    private func tagIds(_ q: DatabaseQueue, entryMerchant: String) throws -> [String] {
        try q.read { db in
            try String.fetchAll(db, sql: """
                SELECT et.tag_id FROM entry_tags et
                JOIN entries e ON e.id = et.entry_id
                WHERE e.description = ? ORDER BY et.tag_id
                """, arguments: [entryMerchant])
        }
    }

    func test_mergeTag_repointsJoin_andDeletesSource() throws {
        let q = try freshDB(); try seed(q)
        try addTx(q, id: "x", tags: ["t2"])   // tagged with the source only
        try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t2"), "targetId": .string("t1")]))
        XCTAssertEqual(try tagIds(q, entryMerchant: "x"), ["t1"])   // repointed
        try q.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM tags WHERE id = 't2'"))   // source gone
        }
    }

    func test_mergeTag_dedups_whenEntryHasBoth() throws {
        let q = try freshDB(); try seed(q)
        try addTx(q, id: "both", tags: ["t1", "t2"])   // has BOTH source and target
        try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t2"), "targetId": .string("t1")]))
        XCTAssertEqual(try tagIds(q, entryMerchant: "both"), ["t1"])   // exactly one row, no dup
    }

    func test_mergeTag_repointsRuleActions() throws {
        let q = try freshDB(); try seed(q)
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "ledgerId": .string("l1"), "id": .string("r1"), "name": .string("R"),
            "condition": .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("z")]),
            "actions": .array([.object(["type": .string("add_tag"), "tagId": .string("t2")])])]))
        try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t2"), "targetId": .string("t1")]))
        try q.read { db in
            let actions = try String.fetchOne(db, sql: "SELECT actions FROM rules WHERE id = 'r1'") ?? ""
            XCTAssertTrue(actions.contains("t1"))
            XCTAssertFalse(actions.contains("t2"))
        }
    }

    func test_mergeTags_manyIntoOne() throws {
        let q = try freshDB(); try seed(q)
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t3"), "ledgerId": .string("l1"), "name": .string("FOOD")]))
        try addTx(q, id: "a", tags: ["t2"]); try addTx(q, id: "b", tags: ["t3"])
        try Apply.apply(dbQueue: q, action: "mergeTags", args: Args([
            "sourceIds": .array([.string("t2"), .string("t3")]), "targetId": .string("t1")]))
        XCTAssertEqual(try tagIds(q, entryMerchant: "a"), ["t1"])
        XCTAssertEqual(try tagIds(q, entryMerchant: "b"), ["t1"])
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE id IN ('t2','t3')"), 0)
        }
    }

    func test_validation() throws {
        let q = try freshDB(); try seed(q)
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("t1"), "targetId": .string("t1")])))   // self
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTag", args: Args(["sourceId": .string("nope"), "targetId": .string("t1")])))   // missing
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTags", args: Args(["sourceIds": .array([]), "targetId": .string("t1")])))   // empty
        // one bad id in a batch aborts the whole batch — t2 must survive
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "mergeTags", args: Args([
            "sourceIds": .array([.string("t2"), .string("nope")]), "targetId": .string("t1")])))
        try q.read { db in XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT id FROM tags WHERE id = 't2'")) }
    }
}
