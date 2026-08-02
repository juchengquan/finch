import XCTest
import GRDB
@testable import FinchCore

/// `Tx.accountLegCount` drives the delete-confirmation hint (ActivityTab /
/// ActivityFeedVC / EditTransactionSheet): "this also deletes the other
/// payment(s)/side(s)" only shows when the entry actually has a sibling
/// account leg. The one parity fixture that carries this field
/// (ParityTests/Fixtures/projection/projection.json) happens to have every
/// row at `1`, so a projection that always reported `1` — dropping the real
/// `GROUP BY entry_id` count entirely — would still pass every existing
/// suite. Assert the field actually discriminates.
final class AccountLegCountProjectionTests: XCTestCase {
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

    func test_accountLegCount_isTwo_forSplitTenderEntry_andOne_forOrdinaryEntry() throws {
        let q = try seedTwoAccounts()

        // An ordinary single-account expense.
        let ordinaryId = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Cafe"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
        ]))!

        // A split-tender purchase paid from both accounts — one entry, two account legs.
        let splitId = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))!

        // `addTransactionReturningId` returns the ENTRY id, but Tx.id is the
        // account POSTING's id (Projection.mapRow) — resolve each entry's
        // posting id(s) to find its feed row(s).
        func postingIds(forEntry entryId: String) throws -> [String] {
            try q.read { db in
                try String.fetchAll(db, sql: "SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [entryId])
            }
        }
        let ordinaryPostingIds = try postingIds(forEntry: ordinaryId)
        XCTAssertEqual(ordinaryPostingIds.count, 1, "an ordinary entry has exactly one account posting")
        let splitPostingIds = try postingIds(forEntry: splitId)
        XCTAssertEqual(splitPostingIds.count, 2, "the split entry has two account postings")

        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")

        let ordinary = try XCTUnwrap(txns.first { $0.id == ordinaryPostingIds[0] })
        XCTAssertEqual(ordinary.accountLegCount, 1, "an ordinary transaction has exactly one account leg")

        let splitRows = txns.filter { splitPostingIds.contains($0.id) }
        XCTAssertEqual(splitRows.count, 2, "a split-tender entry renders one feed row per account leg")
        for row in splitRows {
            XCTAssertEqual(row.accountLegCount, 2, "each row of a two-account entry must report the real leg count")
        }
    }
}
