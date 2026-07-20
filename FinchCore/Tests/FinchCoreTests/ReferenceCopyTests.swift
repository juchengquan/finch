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
}
