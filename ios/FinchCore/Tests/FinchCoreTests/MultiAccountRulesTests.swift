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

    /// A rule's `amount` condition must be evaluated against the BASE-currency
    /// total, not the raw sum of native amounts across legs in different
    /// currencies (which isn't a quantity in any currency). Here a1 (USD -50) +
    /// a2 (EUR -50 @ 1.10) sum to a meaningless "-100" in mixed units, but to
    /// -105 in base (USD). A threshold of 101 distinguishes them: it only fires
    /// if the engine used the coherent base total.
    func test_splitsRule_mixedCurrency_matchesBaseTotalNotRawSum() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Euro Card','credit_card','EUR',0,1,1,1,datetime('now'),datetime('now'))
                """)
            // Seeded rate, not the static fallback, so the base total is exact and
            // reproducible: 1 EUR = 1.10 USD.
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
        }
        let condition: JSONValue = .object([
            "field": .string("amount"), "op": .string("gte"), "value": .double(101)])
        let actions: JSONValue = .array([.object(["type": .string("mark_reviewed")])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Big spend"),
            "condition": condition, "actions": actions]))
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-01", time: "12:00",
                description: "Trip", kind: .expense,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -50)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: -50)),
                    .category(Entries.CategoryLeg(categoryId: "c1", amountBase: 105)),
                ]))
        }
        let reviewedAt = try q.read { db in
            try String.fetchOne(db, sql: "SELECT reviewed_at FROM entries WHERE id = ?", arguments: [eid])
        }
        XCTAssertNotNil(reviewedAt, "amount condition must match the base-currency total (105), not the raw mixed-currency sum (100)")
    }

    /// backfillRule has the same LIMIT-1-rebuild hazard as setTransactionSplits and
    /// bulkRecategorize: a split-tender entry has exactly one category leg, so the
    /// `catCount < 2` gate never skips it, and the categorize would silently drop
    /// every account leg but the one LIMIT 1 fetches. A batch backfill must skip
    /// just this entry's re-categorization and move on, not abort the whole run —
    /// header fields (set_merchant, etc.) and tags for OTHER entries are unaffected.
    func test_backfillRule_onMultiAccountEntry_isSkippedAndKeepsBothLegs() throws {
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
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"), "skipRules": .bool(true),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))!

        let condition: JSONValue = .object([
            "field": .string("merchant"), "op": .string("contains"), "value": .string("Market")])
        let actions: JSONValue = .array([.object(["type": .string("set_category"), "categoryId": .string("c2")])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Market→c2"),
            "condition": condition, "actions": actions]))

        try Apply.apply(dbQueue: q, action: "backfillRule", args: Args(["id": .string("r1")]))

        let (legs, total, catId) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0,
             try String.fetchOne(db, sql: "SELECT category_id FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [eid]))
        }
        XCTAssertEqual(legs, 2, "both payment accounts must survive the skip")
        XCTAssertEqual(total, -100, "…carrying the full amount")
        XCTAssertEqual(catId, "c1", "the category must be untouched — recategorization was skipped for this entry")
    }
}
