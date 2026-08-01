import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountAddTests: XCTestCase {

    private func seedTwoAccounts() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    func test_addTransaction_withTwoAccounts_makesOneEntryWithTwoAccountLegs() throws {
        let q = try seedTwoAccounts()
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))
        let acctLegs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid!])
        }
        XCTAssertEqual(acctLegs, 2, "one entry carrying both payment sources")

        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.isEmpty, "the written entry must be clean: \(problems.map(\.detail))")
    }

    func test_addTransaction_withAccountsNotSummingToAmount_throws() throws {
        let q = try seedTwoAccounts()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-30)]),
            ])])), "shares that don't total the amount must be rejected")
    }

    /// Balances must move on BOTH accounts.
    func test_addTransaction_withTwoAccounts_movesBothBalances() throws {
        let q = try seedTwoAccounts()
        _ = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))
        let (card, cash) = try q.read { db in
            (try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a2'") ?? 0,
             try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id = 'a1'") ?? 0)
        }
        XCTAssertEqual(card, -60)
        XCTAssertEqual(cash, -40)
    }

    /// Splitting the CATEGORY of a purchase that was paid from several ACCOUNTS would
    /// rebuild it from a single account leg and silently drop the rest. Refuse it.
    ///
    /// The split total (40 + 20 = 60) deliberately matches the FIRST account leg's
    /// amount (a2, -60), not the sum of both legs (-100). That is what makes this
    /// test discriminating: a split that totals -100 (e.g. 60 + 40) already trips
    /// the pre-existing `error.split.sumMismatch` check (splitTotal vs the single
    /// fetched leg's magnitude) before the new guard is ever reached, so it "throws"
    /// regardless of whether the guard exists. A split totalling 60 sails past that
    /// old check (60 == 60) and would reach the rebuild — silently dropping a1's -40
    /// leg — unless the multi-account guard stops it first.
    func test_setTransactionSplits_onMultiAccountEntry_isRefusedAndKeepsBothLegs() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))!

        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args([
            "id": .string(eid),
            "splits": .array([
                .object(["categoryId": .string("c1"), "amount": .double(40)]),
                .object(["categoryId": .string("c2"), "amount": .double(20)]),
            ])]))) { error in
            XCTAssertEqual((error as? I18nError)?.code, "error.split.multiAccount",
                            "must be refused by the multi-account guard specifically, not any other validation")
        }

        // The refusal must leave the entry exactly as it was — both payments intact.
        let (legs, total) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0)
        }
        XCTAssertEqual(legs, 2, "both payment accounts must survive the refusal")
        XCTAssertEqual(total, -100, "…carrying the full amount")
    }

    /// bulkRecategorize has the same LIMIT-1-rebuild hazard as setTransactionSplits:
    /// a split-tender entry has exactly one category leg (catCount < 2), so the
    /// existing `catCount >= 2` skip never fires, and the rebuild would silently
    /// drop every account leg but the one LIMIT 1 fetches. Unlike setTransactionSplits
    /// (a single caller that can be told no), this is a bulk loop over many ids — it
    /// must skip the unsafe entry and keep going, not throw.
    func test_bulkRecategorize_onMultiAccountEntry_isSkippedAndKeepsBothLegs() throws {
        let q = try seedTwoAccounts()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))!

        try Apply.apply(dbQueue: q, action: "bulkRecategorize", args: Args([
            "ids": .array([.string(eid)]), "categoryId": .string("c2")]))

        let (legs, total, catId) = try q.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0,
             try Double.fetchOne(db, sql: "SELECT ROUND(SUM(amount_base), 2) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid]) ?? 0,
             try String.fetchOne(db, sql: "SELECT category_id FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [eid]))
        }
        XCTAssertEqual(legs, 2, "both payment accounts must survive the skip")
        XCTAssertEqual(total, -100, "…carrying the full amount")
        XCTAssertEqual(catId, "c1", "the category must be untouched — the whole recategorize was skipped for this entry")
    }

    // MARK: mixed-currency share validation (Fix round 2 — the tolerance bug)

    /// Reconstructs the reviewer's exact false-rejection: two EUR shares (10.01 +
    /// 19.59) each round independently to 10.88 / 21.29 (@ 1.087) = 32.17 base, one
    /// cent off the combined 29.60 EUR rounding to 32.18. Both are correct; a flat
    /// 0.005 tolerance rejected this valid split. `0.005 * (shares.count + 1)` = 0.015
    /// covers it; the split is genuinely valid and must be accepted.
    func test_addTransaction_mixedCurrencySplit_centRoundingWithinTolerance_isAccepted() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Euro Card','credit_card','EUR',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a3','l1','Euro Savings','savings','EUR',0,2,1,1,datetime('now'),datetime('now'))
                """)
            // Seeded explicitly (not the fallback map) so the rate is exact and reproducible.
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.087)")
        }
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-29.60), "currency": .string("EUR"),
            "merchant": .string("Paris Trip"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-10.01)]),
                .object(["accountId": .string("a3"), "amount": .double(-19.59)]),
            ])]))
        XCTAssertNotNil(eid, "a genuinely valid split must not be rejected by rounding noise")

        let acctLegs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid!])
        }
        XCTAssertEqual(acctLegs, 2)
        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.isEmpty, "the written entry must be clean: \(problems.map(\.detail))")
    }

    /// A genuinely wrong split (nowhere near the stated total) must still be
    /// rejected under the widened tolerance — it is not a rounding-noise no-op.
    func test_addTransaction_mixedCurrencySplit_realMismatch_isRejected() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Euro Card','credit_card','EUR',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a3','l1','Euro Savings','savings','EUR',0,2,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.087)")
        }
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-29.60), "currency": .string("EUR"),
            "merchant": .string("Paris Trip"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-10.01)]),
                .object(["accountId": .string("a3"), "amount": .double(-10.00)]),
            ])]))) { error in
            XCTAssertEqual((error as? I18nError)?.code, "error.split.accountsMismatch")
        }
    }
}
