import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountRulesTests: XCTestCase {

    /// A rule's `split` action is SKIPPED on a purchase paid from several
    /// accounts, because that is the rule the rest of the app already enforces:
    /// `setTransactionSplits` refuses such an entry in as many words ("A purchase
    /// paid from several accounts takes a single category"), and the Add sheet
    /// makes the two mutually exclusive. Only the rules engine broke it.
    ///
    /// It matters because the projection copies an entry's whole `splits` array
    /// onto EVERY account-leg row, so a both-axes entry has its category amounts
    /// summed once per payment leg — `categorySpend` reported c1:140/c2:60 for a
    /// $100 purchase, and a budget alert fired at twice the real spend.
    ///
    /// This test previously asserted the opposite: that the split distributed
    /// 70/30 over the total. That shape is now refused outright, so the entry
    /// keeps the single category it was posted with.
    func test_splitsRule_onTwoAccountEntry_isSkipped_andOtherActionsStillApply() throws {
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
        // A split action AND a plain one, so the test can tell "the split was
        // skipped" from "the whole rule was skipped".
        let actions: JSONValue = .array([
            .object([
                "type": .string("split"),
                "splits": .array([
                    .object(["fraction": .double(0.7), "categoryId": .string("c1")]),
                    .object(["fraction": .double(0.3), "categoryId": .string("c2")]),
                ])]),
            .object(["type": .string("set_merchant"), "merchant": .string("Market Ltd")]),
        ])
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
        let (catLegs, c1, c2, merchant) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [eid]) ?? 0,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND category_id = 'c1'", arguments: [eid]) ?? 0,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND category_id = 'c2'", arguments: [eid]) ?? 0,
             try String.fetchOne(db, sql: "SELECT description FROM entries WHERE id = ?", arguments: [eid]))
        }
        XCTAssertEqual(catLegs, 1, "the split is skipped, so the single posted category leg survives")
        XCTAssertEqual(c1, 100, accuracy: 0.001, "carrying the whole purchase")
        XCTAssertEqual(c2, 0, accuracy: 0.001, "the rule's second category was never created")
        XCTAssertEqual(merchant, "Market Ltd", "the rule's OTHER actions still apply — only `split` is skipped")

        // The reason the shape is refused: the projection copies an entry's splits
        // onto every account-leg row, so a both-axes entry is summed once per leg.
        // Before this fix these read c1:140 and c2:60 for a $100 purchase.
        let spend = Selectors.categorySpend(try Projection.run(dbQueue: q, ledgerId: "l1"), "l1")
        XCTAssertEqual(spend["c1"] ?? 0, 100, accuracy: 0.001, "a $100 purchase counts as $100, not $140")
        XCTAssertNil(spend["c2"], "and nothing lands in a category the entry does not have")
    }

    /// A rule whose ONLY action is a skipped split did nothing, so it must not
    /// claim a match — `appliedRuleIds` drives the "matched N times" count on the
    /// rules screen, and a rule reporting matches while changing nothing is worse
    /// than one reporting none.
    func test_splitOnlyRule_onTwoAccountEntry_isNotRecordedAsApplied() throws {
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
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Split only"),
            "condition": .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("Market")]),
            "actions": .array([.object([
                "type": .string("split"),
                "splits": .array([
                    .object(["fraction": .double(0.7), "categoryId": .string("c1")]),
                    .object(["fraction": .double(0.3), "categoryId": .string("c2")]),
                ])])])]))
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
        let applied = try q.read { db in
            try String.fetchOne(db, sql: "SELECT applied_rule_ids FROM entries WHERE id = ?", arguments: [eid])
        }
        XCTAssertTrue(applied == nil || applied == "" || applied == "[]",
                      "a rule that only tried to split must not claim a match: got \(applied ?? "nil")")
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
