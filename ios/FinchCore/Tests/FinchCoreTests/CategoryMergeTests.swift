import XCTest
import GRDB
@testable import FinchCore

final class CategoryMergeTests: XCTestCase {
    /// Ledger, two cash accounts, and two same-kind (expense) categories:
    /// cSource (absorbed) and cTarget (survivor).
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            for a in ["a1", "a2"] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash','USD',0,0,1,1,datetime('now'),datetime('now'))", arguments: [a, a])
            }
            for c in ["cSource", "cTarget"] {
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }

    private func merge(_ q: DatabaseQueue, _ source: String, _ target: String) throws {
        try Apply.apply(dbQueue: q, action: "mergeCategory", args: Args(["sourceId": .string(source), "targetId": .string(target)]))
    }

    func test_transaction_and_split_legs_repoint_to_target() throws {
        let q = try seeded()
        // A plain expense categorized to cSource…
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string("x"), "categoryId": .string("cSource"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        // …and a split with one leg on cSource. addTransaction has no inline
        // "splits" param (Transactions.AddInput doesn't decode one) — splits are
        // attached via the separate setTransactionSplits action, entry-id-addressed.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-10),
            "merchant": .string("y"), "date": .string("2026-05-02"), "skipRules": .bool(true)]))
        let splitEntryId = try q.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM entries WHERE description = 'y'")!
        }
        try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args([
            "id": .string(splitEntryId),
            "splits": .array([
                .object(["categoryId": .string("cSource"), "amount": .double(-4)]),
                .object(["categoryId": .string("cTarget"), "amount": .double(-6)]),
            ])]))
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id = 'cTarget'"), 3) // 1 plain + 2 split legs
        }
    }

    func test_scheduled_split_repoints_and_delete_succeeds() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO scheduled_templates (id,ledger_id,kind,account_id,category_id,frequency,start_date,created_at,updated_at) VALUES ('st1','l1','expense','a1','cSource','monthly','2026-05-01',datetime('now'),datetime('now'))")
            // scheduled_splits.category_id is ON DELETE RESTRICT — a plain delete of cSource would fail.
            try db.execute(sql: "INSERT INTO scheduled_splits (id,template_id,account_id,amount_abs,category_id,sort_order) VALUES ('ss1','st1','a1',10,'cSource',0)")
        }
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM scheduled_splits WHERE id = 'ss1'"), "cTarget")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM scheduled_templates WHERE id = 'st1'"), "cTarget")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cSource'"), 0) // RESTRICT cleared → delete OK
        }
    }

    func test_budget_category_ids_rewritten_and_deduped() throws {
        let q = try seeded()
        try q.write { db in
            // one budget listing cSource + cOther, one already listing both cSource + cTarget (dedup case)
            try db.execute(sql: "INSERT INTO budgets (id,ledger_id,kind,amount,frequency,start_date,category_ids,created_at,updated_at) VALUES ('b1','l1','expense',100,'monthly','2026-05-01','[\"cSource\",\"cOther\"]',datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO budgets (id,ledger_id,kind,amount,frequency,start_date,category_ids,created_at,updated_at) VALUES ('b2','l1','expense',100,'monthly','2026-05-01','[\"cSource\",\"cTarget\"]',datetime('now'),datetime('now'))")
        }
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_ids FROM budgets WHERE id = 'b1'"), "[\"cTarget\",\"cOther\"]")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_ids FROM budgets WHERE id = 'b2'"), "[\"cTarget\"]") // deduped
        }
    }

    func test_child_reparents_under_target() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cSource','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = 'cKid'"), "cTarget")
        }
    }

    /// When a merged-away category's children cannot fit under the target, they are
    /// promoted to the top level rather than dropped. Built from `Categories.maxDepth`
    /// so it keeps exercising the fallback wherever the limit sits — the previous
    /// version hardcoded a 2-deep target plus a 2-deep subtree, which stopped
    /// overflowing the moment the cap moved past 4 and silently tested nothing.
    func test_child_falls_back_to_top_level_when_depth_would_exceed_cap() throws {
        let q = try seeded()
        try q.write { db in
            // A target chain deep enough that two more levels overflow.
            var parent: String? = nil
            for level in 0..<(Categories.maxDepth - 1) {
                let id = "p\(level)"
                try db.execute(
                    sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',?,?,'expense',0,datetime('now'),datetime('now'))",
                    arguments: [id, parent, id.uppercased()])
                parent = id
            }
            try db.execute(
                sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('deepTarget','l1',?,'DT','expense',0,datetime('now'),datetime('now'))",
                arguments: [parent])
            // The source's child has a child of its own — a 2-level subtree.
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cSource','Kid','expense',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cGrandkid','l1','cKid','GK','expense',0,datetime('now'),datetime('now'))")
        }
        try merge(q, "cSource", "deepTarget")
        try q.read { db in
            // depth(deepTarget) = maxDepth, subtreeDepth(cKid) = 2 ⇒ overflow, so cKid
            // is promoted to the top level instead of being nested or lost.
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT parent_id FROM categories WHERE id = 'cKid'"))
            // And nothing was destroyed on the way.
            XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT id FROM categories WHERE id = 'cGrandkid'"))
        }
    }

    func test_source_row_is_deleted() throws {
        let q = try seeded()
        try merge(q, "cSource", "cTarget")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'cTarget'"), 1)
        }
    }

    func test_merge_into_self_is_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try merge(q, "cSource", "cSource"))
    }

    func test_missing_source_or_target_is_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try merge(q, "nope", "cTarget"))
        XCTAssertThrowsError(try merge(q, "cSource", "nope"))
    }

    func test_merge_into_own_descendant_is_rejected() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cKid','l1','cSource','Kid','expense',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try merge(q, "cSource", "cKid"))  // target is a descendant of source
    }

    func test_cross_kind_merge_is_rejected() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cIncome','l1',NULL,'Salary','income',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try merge(q, "cSource", "cIncome"))
    }
}
