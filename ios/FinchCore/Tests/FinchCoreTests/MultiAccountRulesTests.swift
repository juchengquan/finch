import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountRulesTests: XCTestCase {

    /// A splits rule must distribute over the TOTAL of the account legs, not the
    /// first one, or the entry cannot balance and the seal aborts.
    func test_splitsRule_onTwoAccountEntry_balances() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
        }
        // Build the rule through the action, not raw SQL — the `rules` table stores
        // `condition` and `actions` as JSON blobs (NOT `match_json`/`actions_json`),
        // and `createRule` is what the rest of the suite uses. Shape copied from
        // BackfillRuleTests.swift:27-29; the "split" action shape is
        // RulesEngine.swift:111-116.
        let condition: JSONValue = .object([
            "field": .string("merchant"), "op": .string("contains"), "value": .string("Market")])
        let actions: JSONValue = .array([.object([
            "type": .string("split"),
            "splits": .array([
                .object(["fraction": .double(0.7), "categoryId": .string("c1")]),
                .object(["fraction": .double(0.3), "categoryId": .string("c2")]),
            ])])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Split market"),
            "condition": condition, "actions": actions]))
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Market", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a2", amount: -60)),
                    .account(Entries.AccountLeg(accountId: "a1", amount: -40)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 100)),
                ]))
        }
        // Assert the PER-CATEGORY amounts. Totals cannot discriminate: appendResidue
        // force-balances the shortfall into a sys:fx equity leg, which is itself a
        // category leg, so the buggy path's c1=42 / c2=18 / fx=40 and the correct
        // path's c1=70 / c2=30 both sum to 100.
        let (c1, c2, fxLegs) = try q.read { db in
            (try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND category_id = 'c1'", arguments: [eid]) ?? 0,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND category_id = 'c2'", arguments: [eid]) ?? 0,
             try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM postings p JOIN categories c ON c.id = p.category_id
                 WHERE p.entry_id = ? AND c.system = 'fx'
                """, arguments: [eid]) ?? 0)
        }
        XCTAssertEqual(c1, 70, accuracy: 0.001, "70% of the FULL 100, not of the first leg's 60")
        XCTAssertEqual(c2, 30, accuracy: 0.001, "30% of the FULL 100, not of the first leg's 60")
        XCTAssertEqual(fxLegs, 0, "no phantom fx residue — a domestic purchase has no exchange-rate remainder")
    }
}
