import XCTest
import GRDB
@testable import FinchCore

/// A rule names categories, merchants and tags by id. Merging or deleting one of
/// those used to leave the rule pointing at a row that no longer exists, and the
/// next matching write died on the FOREIGN KEY check — from the Add sheet, Siri,
/// the Watch and CSV import alike.
final class RuleRefsTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            for c in ["groceries", "food", "other"] {
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }

    private func rule(_ q: DatabaseQueue, _ id: String, condition: JSONValue, actions: [JSONValue]) throws {
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string(id), "ledgerId": .string("l1"), "condition": condition, "actions": .array(actions)]))
    }

    private func add(_ q: DatabaseQueue, _ merchant: String, category: String = "other", amount: Double = -12) throws {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amount),
            "merchant": .string(merchant), "categoryId": .string(category), "date": .string("2026-05-01")]))
    }

    private func categoryOf(_ q: DatabaseQueue, _ merchant: String) throws -> String? {
        try q.read { db in
            try String.fetchOne(db, sql: """
                SELECT p.category_id FROM postings p JOIN entries e ON e.id = p.entry_id
                 WHERE e.description = ? AND p.account_id IS NULL
                """, arguments: [merchant])
        }
    }

    private let wholeFoods: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("whole")])

    func test_after_a_category_merge_the_rule_sets_the_survivor() throws {
        let q = try seeded()
        try rule(q, "r1", condition: wholeFoods, actions: [.object(["type": .string("set_category"), "categoryId": .string("groceries")])])
        try Apply.apply(dbQueue: q, action: "mergeCategory", args: Args(["sourceId": .string("groceries"), "targetId": .string("food")]))
        try add(q, "Whole Foods")   // threw "FOREIGN KEY constraint failed" before
        XCTAssertEqual(try categoryOf(q, "Whole Foods"), "food")
    }

    func test_a_category_merge_repoints_conditions_and_split_actions() throws {
        let q = try seeded()
        let condition: JSONValue = .object(["any": .array([
            .object(["field": .string("category_id"), "op": .string("is"), "value": .string("groceries")]),
            .object(["field": .string("category_id"), "op": .string("in"), "value": .array([.string("groceries"), .string("food")])]),
        ])])
        try rule(q, "r1", condition: condition, actions: [.object(["type": .string("split"), "splits": .array([
            .object(["fraction": .double(0.5), "categoryId": .string("groceries")]),
            .object(["fraction": .double(0.5), "categoryId": .string("other")]),
        ])])])
        try Apply.apply(dbQueue: q, action: "mergeCategory", args: Args(["sourceId": .string("groceries"), "targetId": .string("food")]))
        let (cond, acts) = try q.read { db in
            (try String.fetchOne(db, sql: "SELECT condition FROM rules WHERE id = 'r1'")!,
             try String.fetchOne(db, sql: "SELECT actions FROM rules WHERE id = 'r1'")!)
        }
        XCTAssertFalse(cond.contains("groceries"), cond)
        XCTAssertFalse(acts.contains("groceries"), acts)
        // `in` lists stay duplicate-free once the source becomes the target.
        XCTAssertTrue(cond.contains(#""value":["food"]"#), cond)
        // The rule still fires and splits against the survivor.
        try add(q, "Anything", category: "food")
        let cats = try q.read { db in
            try String.fetchAll(db, sql: "SELECT category_id FROM postings WHERE account_id IS NULL ORDER BY category_id")
        }
        XCTAssertEqual(cats, ["food", "other"])
    }

    func test_after_a_merchant_merge_the_rule_sets_the_survivor() throws {
        let q = try seeded()
        for (id, name) in [("cpOld", "WFM"), ("cpNew", "Whole Foods Market")] {
            try Apply.apply(dbQueue: q, action: "createCounterparty", args: Args(["id": .string(id), "name": .string(name)]))
        }
        try rule(q, "r1", condition: wholeFoods, actions: [.object(["type": .string("set_counterparty"), "counterpartyId": .string("cpOld")])])
        try Apply.apply(dbQueue: q, action: "mergeCounterparty", args: Args(["sourceId": .string("cpOld"), "targetId": .string("cpNew")]))
        try add(q, "Whole Foods")
        let cp = try q.read { db in try String.fetchOne(db, sql: "SELECT counterparty_id FROM entries WHERE description = 'Whole Foods'") }
        XCTAssertEqual(cp, "cpNew")
    }

    func test_after_a_delete_the_dangling_actions_are_skipped_and_the_rest_apply() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("trip")]))
        try Apply.apply(dbQueue: q, action: "createCounterparty", args: Args(["id": .string("cp1"), "name": .string("WFM")]))
        try rule(q, "r1", condition: wholeFoods, actions: [
            .object(["type": .string("set_category"), "categoryId": .string("groceries")]),
            .object(["type": .string("set_counterparty"), "counterpartyId": .string("cp1")]),
            .object(["type": .string("add_tag"), "tagId": .string("t1")]),
            .object(["type": .string("set_note"), "note": .string("weekly shop")]),
        ])
        try Apply.apply(dbQueue: q, action: "deleteCategory", args: Args(["id": .string("groceries")]))
        try Apply.apply(dbQueue: q, action: "deleteCounterparty", args: Args(["id": .string("cp1")]))
        try Apply.apply(dbQueue: q, action: "deleteTag", args: Args(["id": .string("t1")]))
        try add(q, "Whole Foods")
        XCTAssertEqual(try categoryOf(q, "Whole Foods"), "other")
        let note = try q.read { db in try String.fetchOne(db, sql: "SELECT notes FROM entries WHERE description = 'Whole Foods'") }
        XCTAssertEqual(note, "weekly shop")
    }

    func test_backfill_with_a_deleted_category_skips_the_recategorise() throws {
        let q = try seeded()
        try add(q, "Whole Foods", category: "other")
        try rule(q, "r1", condition: wholeFoods, actions: [.object(["type": .string("set_category"), "categoryId": .string("groceries")])])
        try Apply.apply(dbQueue: q, action: "deleteCategory", args: Args(["id": .string("groceries")]))
        try Apply.apply(dbQueue: q, action: "backfillRule", args: Args(["id": .string("r1")]))
        XCTAssertEqual(try categoryOf(q, "Whole Foods"), "other")
    }

    /// A `set_kind=transfer` rule backfilled over an expense wrote a kind the entry's
    /// legs can't have; the audit then refused every backup taken afterwards.
    func test_backfill_never_writes_a_kind_the_entry_cannot_have() throws {
        let q = try seeded()
        try add(q, "Whole Foods")
        for (id, kind) in [("r1", "transfer"), ("r2", "adjustment"), ("r3", "refund")] {
            try rule(q, id, condition: wholeFoods, actions: [.object(["type": .string("set_kind"), "kind": .string(kind)])])
            try Apply.apply(dbQueue: q, action: "backfillRule", args: Args(["id": .string(id)]))
        }
        let kind = try q.read { db in try String.fetchOne(db, sql: "SELECT kind FROM entries WHERE description = 'Whole Foods'") }
        XCTAssertEqual(kind, "expense")   // refund too: money went out, so it can't be one
        let problems = try Audit.run(on: q, ledgerId: "l1")
        XCTAssertTrue(problems.isEmpty, "\(problems)")
    }

    func test_backfill_still_rekinds_to_a_kind_that_fits() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('pay','l1',NULL,'pay','income',0,datetime('now'),datetime('now'))")
        }
        try add(q, "Whole Foods", category: "pay", amount: 30)
        try rule(q, "r1", condition: wholeFoods, actions: [.object(["type": .string("set_kind"), "kind": .string("refund")])])
        try Apply.apply(dbQueue: q, action: "backfillRule", args: Args(["id": .string("r1")]))
        let kind = try q.read { db in try String.fetchOne(db, sql: "SELECT kind FROM entries WHERE description = 'Whole Foods'") }
        XCTAssertEqual(kind, "refund")
    }
}
