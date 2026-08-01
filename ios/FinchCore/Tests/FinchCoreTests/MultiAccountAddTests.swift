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
}
