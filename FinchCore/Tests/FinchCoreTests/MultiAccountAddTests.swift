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
}
