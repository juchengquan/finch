import XCTest
import GRDB
@testable import FinchCore

/// Through-the-chokepoint tests for the simpler CRUD domains + tag/recategorize.
final class DomainCrudTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1 (Food)
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c2','l1',NULL,'Transport','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_counterpartyCrud() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createCounterparty", args: Args(["id": .string("cp1"), "ledgerId": .string("l1"), "name": .string("Starbucks")]))
        try Apply.apply(dbQueue: q, action: "verifyCounterparty", args: Args(["id": .string("cp1")]))
        try Apply.apply(dbQueue: q, action: "updateCounterparty", args: Args(["id": .string("cp1"), "patch": .object(["name": .string("Starbucks Reserve")])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM counterparties WHERE id='cp1'"), "Starbucks Reserve")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_verified FROM counterparties WHERE id='cp1'"), 1)
        }
        try Apply.apply(dbQueue: q, action: "deleteCounterparty", args: Args(["id": .string("cp1")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties") }, 0)
    }

    func test_tagCrud_emptyNameRejected() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("travel"), "color": .string("#f00")]))
        XCTAssertEqual(try q.read { db in try String.fetchOne(db, sql: "SELECT color FROM tags WHERE id='t1'") }, "#f00")
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createTag", args: Args(["name": .string("   ")]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.required.tagName")
        }
    }

    func test_setTransactionTags() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("travel")]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args(["ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25), "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        let txId = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id='a1'")! }
        try Apply.apply(dbQueue: q, action: "setTransactionTags", args: Args(["id": .string(txId), "tagIds": .array([.string("t1")])]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags") }, 1)
    }

    func test_accountGroupCrud() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createAccountGroup", args: Args(["id": .string("ag1"), "ledgerId": .string("l1"), "name": .string("Cash")]))
        try Apply.apply(dbQueue: q, action: "createAccountGroup", args: Args(["id": .string("ag2"), "ledgerId": .string("l1"), "name": .string("Cards")]))
        try Apply.apply(dbQueue: q, action: "updateAccountGroup", args: Args(["id": .string("ag1"), "patch": .object(["name": .string("Liquid")])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM account_groups WHERE id='ag1'"), "Liquid")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT sort_order FROM account_groups WHERE id='ag2'"), 1)
        }
        try Apply.apply(dbQueue: q, action: "deleteAccountGroup", args: Args(["id": .string("ag2")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM account_groups") }, 1)
    }

    func test_budgetGroupCrud() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createBudgetGroup", args: Args(["id": .string("bg1"), "ledgerId": .string("l1"), "name": .string("Essentials")]))
        try Apply.apply(dbQueue: q, action: "updateBudgetGroup", args: Args(["id": .string("bg1"), "patch": .object(["name": .string("Needs")])]))
        XCTAssertEqual(try q.read { db in try String.fetchOne(db, sql: "SELECT name FROM budget_groups WHERE id='bg1'") }, "Needs")
    }

    func test_categoryCrud() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createCategory", args: Args(["id": .string("c3"), "ledgerId": .string("l1"), "name": .string("Coffee"), "type": .string("expense"), "color": .string("#abc")]))
        try Apply.apply(dbQueue: q, action: "updateCategory", args: Args(["id": .string("c3"), "patch": .object(["name": .string("Cafés"), "color": .null])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM categories WHERE id='c3'"), "Cafés")
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT color FROM categories WHERE id='c3'"))
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT kind FROM categories WHERE id='c3'"), "expense")
        }
        // self-parent guard
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "updateCategory", args: Args(["id": .string("c3"), "patch": .object(["parentId": .string("c3")])]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.category.selfParent")
        }
    }

    func test_bulkRecategorize() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args(["ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25), "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        let txId = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id='a1'")! }
        try Apply.apply(dbQueue: q, action: "bulkRecategorize", args: Args(["ids": .array([.string(txId)]), "categoryId": .string("c2")]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM postings WHERE category_id IS NOT NULL"), "c2")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? -1, -25, accuracy: 0.001)
        }
    }
}
