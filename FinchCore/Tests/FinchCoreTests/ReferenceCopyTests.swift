import XCTest
import GRDB
@testable import FinchCore

final class ReferenceCopyTests: XCTestCase {
    /// Two ledgers l1 (source) + l2 (target). No system rows (not needed for copy logic).
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            for l in ["l1", "l2"] {
                try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES (?,?,'USD',0,datetime('now'),datetime('now'))", arguments: [l, l])
            }
        }
        return q
    }
    private func cat(_ q: DatabaseQueue, _ id: String, _ ledger: String, _ name: String, kind: String = "expense", parent: String? = nil, system: String? = nil) throws {
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,system,created_at,updated_at) VALUES (?,?,?,?,?,0,?,datetime('now'),datetime('now'))",
                           arguments: [id, ledger, parent, name, kind, system])
        }
    }
    private func tag(_ q: DatabaseQueue, _ id: String, _ ledger: String, _ name: String) throws {
        try q.write { db in try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,created_at,updated_at) VALUES (?,?,?,datetime('now'),datetime('now'))", arguments: [id, ledger, name]) }
    }
    private func names(_ q: DatabaseQueue, _ table: String, _ ledger: String) throws -> [String] {
        try q.read { db in try String.fetchAll(db, sql: "SELECT name FROM \(table) WHERE ledger_id = ? ORDER BY name", arguments: [ledger]) }
    }

    func test_copyTags_additive_dedup_idempotent() throws {
        let q = try seeded()
        try tag(q, "t1", "l1", "food"); try tag(q, "t2", "l1", "travel")
        try tag(q, "t3", "l2", "Travel")   // already present (case-insensitive dup)
        try Apply.apply(dbQueue: q, action: "copyTags", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")]))
        // tags.name has no COLLATE NOCASE (unlike counterparties.name), so ORDER BY
        // name is binary — capital "Travel" sorts before lowercase "food".
        XCTAssertEqual(try names(q, "tags", "l2"), ["Travel", "food"])   // food added, Travel not duplicated
        // idempotent
        try Apply.apply(dbQueue: q, action: "copyTags", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")]))
        XCTAssertEqual(try names(q, "tags", "l2").count, 2)
    }

    func test_copyTags_ids_scopes_to_named() throws {
        let q = try seeded()
        try tag(q, "t1", "l1", "food"); try tag(q, "t2", "l1", "travel")
        try Apply.apply(dbQueue: q, action: "copyTags", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2"), "ids": .array([.string("t1")])]))
        XCTAssertEqual(try names(q, "tags", "l2"), ["food"])
    }

    func test_copyCategories_preserves_tree_and_dedups() throws {
        let q = try seeded()
        try cat(q, "cFood", "l1", "Food"); try cat(q, "cCoffee", "l1", "Coffee", parent: "cFood")
        try cat(q, "cSys", "l1", "Opening", kind: "equity", system: "opening")  // system → must be skipped
        try cat(q, "cFoodT", "l2", "Food")   // dup at top level → child should attach under it
        try Apply.apply(dbQueue: q, action: "copyCategories", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")]))
        try q.read { db in
            // "Food" not duplicated; "Coffee" added under the existing "Food"; system skipped.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE ledger_id='l2' AND name='Food'"), 1)
            let coffeeParent = try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE ledger_id='l2' AND name='Coffee'")
            XCTAssertEqual(coffeeParent, "cFoodT")
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM categories WHERE ledger_id='l2' AND name='Opening'"))
        }
    }

    func test_copyCategories_ids_includes_ancestors() throws {
        let q = try seeded()
        try cat(q, "cFood", "l1", "Food"); try cat(q, "cCoffee", "l1", "Coffee", parent: "cFood")
        try Apply.apply(dbQueue: q, action: "copyCategories", args: Args(["fromLedgerId": .string("l1"), "toLedgerId": .string("l2"), "ids": .array([.string("cCoffee")])]))
        // Coffee copied + its ancestor Food, tree intact.
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE ledger_id='l2'"), 2)
            let cp = try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE ledger_id='l2' AND name='Coffee'")
            let foodId = try String.fetchOne(db, sql: "SELECT id FROM categories WHERE ledger_id='l2' AND name='Food'")
            XCTAssertEqual(cp, foodId)
        }
    }

    // MARK: added-count (drives the "N added" confirmation)

    private func copyCount(_ q: DatabaseQueue, _ action: String, _ args: [String: JSONValue]) throws -> Int {
        try Apply.applyReturningCount(dbQueue: q, action: action, args: Args(args))
    }

    /// The count is NEW inserts only, so a re-copy reports 0 rather than
    /// re-reporting rows that were merely matched.
    func test_copyTags_countsOnlyNewInserts() throws {
        let q = try seeded()
        try tag(q, "t1", "l1", "food"); try tag(q, "t2", "l1", "travel")
        try tag(q, "t3", "l2", "Food")          // already there (case-insensitive match)
        let first = try copyCount(q, "copyTags", ["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")])
        XCTAssertEqual(first, 1, "only 'travel' is new")
        let again = try copyCount(q, "copyTags", ["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")])
        XCTAssertEqual(again, 0, "nothing new on a re-copy")
    }

    /// Two SOURCE tags differing only in case must collapse to one insert — the
    /// dedup set is updated as we go, not snapshotted before the loop.
    func test_copyTags_sourceCaseDuplicatesCollapse() throws {
        let q = try seeded()
        try tag(q, "t1", "l1", "Food"); try tag(q, "t2", "l1", "food")
        let n = try copyCount(q, "copyTags", ["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")])
        XCTAssertEqual(n, 1)
        XCTAssertEqual(try names(q, "tags", "l2").count, 1, "no duplicate landed in the target")
    }

    /// Categories count new inserts only; a reused ancestor doesn't inflate it.
    func test_copyCategories_countsOnlyNewInserts() throws {
        let q = try seeded()
        try cat(q, "cFood", "l1", "Food"); try cat(q, "cCoffee", "l1", "Coffee", parent: "cFood")
        let first = try copyCount(q, "copyCategories", ["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")])
        XCTAssertEqual(first, 2, "Food + Coffee")
        let again = try copyCount(q, "copyCategories", ["fromLedgerId": .string("l1"), "toLedgerId": .string("l2")])
        XCTAssertEqual(again, 0, "both matched on a re-copy")
    }

    /// Non-copy actions report 0 rather than a misleading number.
    func test_applyReturningCount_isZeroForOtherActions() throws {
        let q = try seeded()
        let n = try copyCount(q, "createTag", ["ledgerId": .string("l1"), "name": .string("new")])
        XCTAssertEqual(n, 0)
    }
}
