import XCTest
import GRDB
@testable import FinchCore

final class CategoryMergeMultiTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','a1','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            for c in ["cKeep", "cB", "cC"] {  // cKeep = survivor/target; cB,cC = absorbed
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }
    private func addTx(_ q: DatabaseQueue, _ id: String, _ cat: String) throws {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string(id), "categoryId": .string(cat), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
    }
    private func mergeMany(_ q: DatabaseQueue, _ sources: [String], _ target: String) throws {
        try Apply.apply(dbQueue: q, action: "mergeCategories",
                        args: Args(["sourceIds": .array(sources.map(JSONValue.string)), "targetId": .string(target)]))
    }

    func test_all_sources_repoint_and_are_deleted() throws {
        let q = try seeded()
        try addTx(q, "t1", "cB")
        try addTx(q, "t2", "cC")
        try mergeMany(q, ["cB", "cC"], "cKeep")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id IN ('cB','cC')"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cKeep'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id IN ('cB','cC')"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cKeep'"), 1)
        }
    }

    func test_child_of_a_source_reparents_under_target() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cB','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        try mergeMany(q, ["cB"], "cKeep")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = 'cKid'"), "cKeep")
        }
    }

    func test_bad_source_rejects_and_leaves_everything_untouched() throws {
        let q = try seeded()
        try addTx(q, "t1", "cB")
        try q.write { db in  // cC2 is INCOME — cross-kind, must abort the whole set
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cInc','l1',NULL,'Salary','income',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try mergeMany(q, ["cB", "cInc"], "cKeep"))
        try q.read { db in  // cB's tx NOT repointed, cB still present — nothing merged
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cB'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cB'"), 1)
        }
    }

    func test_target_in_sources_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try mergeMany(q, ["cB", "cKeep"], "cKeep"))
    }

    func test_empty_sources_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try mergeMany(q, [], "cKeep"))
    }

    func test_descendant_target_rejected() throws {
        let q = try seeded()
        try q.write { db in  // cKid is a child of cB; merging cB into cKid = into own descendant
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cB','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try mergeMany(q, ["cB"], "cKid"))
    }

    func test_three_sources_all_repoint_and_are_deleted() throws {
        let q = try seeded()  // seeds cKeep, cB, cC
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cD','l1',NULL,'cD','expense',0,datetime('now'),datetime('now'))")
        }
        try addTx(q, "t1", "cB"); try addTx(q, "t2", "cC"); try addTx(q, "t3", "cD")
        try mergeMany(q, ["cB", "cC", "cD"], "cKeep")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cKeep'"), 3)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id IN ('cB','cC','cD')"), 0)
        }
    }
}
