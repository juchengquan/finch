import XCTest
import GRDB
@testable import FinchCore

final class BackfillRuleTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            for c in ["c1", "c2"] {
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }

    /// A merchant-match rule that sets a category, backfilled onto an existing
    /// confirmed expense, re-categorizes its category leg.
    func test_backfillRecategorizes() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Blue Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true),
        ]))
        let condition: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")])
        let actions: JSONValue = .array([.object(["type": .string("set_category"), "categoryId": .string("c2")])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args(["id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Coffee→c2"), "condition": condition, "actions": actions]))

        try Apply.apply(dbQueue: q, action: "backfillRule", args: Args(["id": .string("r1")]))
        try q.read { db in
            // the category posting moved c1 → c2; still balanced; balance unchanged
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM postings WHERE category_id IS NOT NULL"), "c2")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base),2) FROM postings p JOIN entries e ON e.id=p.entry_id WHERE e.kind='expense'") ?? -1, 0, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? 0, -25, accuracy: 0.001)
            XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT last_applied_at FROM rules WHERE id='r1'") ?? nil)
        }
    }

    /// A set_merchant rule writes the entry header (description) + applied_rule_ids.
    func test_backfillSetsMerchantHeader() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-9),
            "merchant": .string("SQ *BLUE BOTTLE"), "categoryId": .string("c1"), "date": .string("2026-05-02"), "skipRules": .bool(true),
        ]))
        let condition: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("blue bottle")])
        let actions: JSONValue = .array([.object(["type": .string("set_merchant"), "merchant": .string("Blue Bottle")])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args(["id": .string("r1"), "ledgerId": .string("l1"), "condition": condition, "actions": actions]))
        try Apply.apply(dbQueue: q, action: "backfillRule", args: Args(["id": .string("r1")]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT description FROM entries"), "Blue Bottle")
            let applied = try String.fetchOne(db, sql: "SELECT applied_rule_ids FROM entries") ?? ""
            XCTAssertTrue(applied.contains("r1"), applied)
        }
    }

    /// The Phase 4 rules projection lists name/priority/active.
    func test_rulesProjection() throws {
        let q = try seeded()
        let condition: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("x")])
        let actions: JSONValue = .array([.object(["type": .string("set_reviewed")])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args(["id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Rev"), "priority": .int(50), "condition": condition, "actions": actions]))
        try Apply.apply(dbQueue: q, action: "updateRule", args: Args(["id": .string("r1"), "patch": .object(["isActive": .bool(false)])]))
        let rules = try Projection.rules(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.name, "Rev")
        XCTAssertEqual(rules.first?.priority, 50)
        XCTAssertEqual(rules.first?.isActive, false)
    }

    /// On-insert: an active set_category rule fires inside addTransaction (the
    /// postEntry rules hook), re-pointing the category leg and stamping
    /// applied_rule_ids — without a separate backfill pass.
    func test_rulesApplyOnInsert() throws {
        let q = try seeded()
        let condition: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")])
        let actions: JSONValue = .array([.object(["type": .string("set_category"), "categoryId": .string("c2")])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args(["id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Coffee→c2"), "condition": condition, "actions": actions]))
        // categoryId c1 in args, but the rule should re-point it to c2 on insert.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Blue Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"),
        ]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM postings WHERE category_id IS NOT NULL"), "c2")
            let applied = try String.fetchOne(db, sql: "SELECT applied_rule_ids FROM entries") ?? ""
            XCTAssertTrue(applied.contains("r1"), applied)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? 0, -25, accuracy: 0.001)
        }
        // skipRules bypasses the hook → category stays c1.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string("More Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-03"), "skipRules": .bool(true),
        ]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE category_id='c1'"), 1)
        }
    }
}
