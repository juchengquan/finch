import XCTest
import GRDB
@testable import FinchCore

/// `Tx.entryId` is the join key that lets a purchase be reconstructed from a
/// `[Tx]` array. Without it there is none: `Tx.id` is the account POSTING's id
/// (`Projection.selectSQL` selects `p.id AS pid`), and `accountLegCount` is a
/// flag, not something you can group by. So a purchase paid from two accounts —
/// one entry, two feed rows — is counted twice everywhere that counts rows.
///
/// It is stamped for EVERY row, not only multi-leg ones. A conditional field
/// would force every call site to remember a fallback, and the one that forgot
/// would be silently wrong rather than broken.
final class EntryIdProjectionTests: XCTestCase {
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

    func test_entryId_isStampedOnEveryRow_andGroupsASplitTenderPurchase() throws {
        let q = try seedTwoAccounts()

        let ordinaryId = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Cafe"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
        ]))!

        // One purchase, paid $60 from the card and $40 from the account.
        let splitId = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))!

        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")

        // The grain is unchanged: still one row per account leg. This fix is about
        // being able to group them, not about emitting fewer rows.
        let splitRows = txns.filter { $0.entryId == splitId }
        XCTAssertEqual(splitRows.count, 2, "a split-tender entry still renders one row per account leg")
        XCTAssertEqual(Set(splitRows.map(\.amount)), [-60, -40], "and each row keeps its own leg amount")

        // The distinction the whole plan rests on: entryId names the purchase,
        // id names the payment. Equal ids would make grouping a no-op that still
        // passed a weaker assertion.
        for row in splitRows {
            XCTAssertNotEqual(row.entryId, row.id, "entryId is the entry; id is the posting")
        }

        // Stamped unconditionally — an ordinary single-leg row carries it too.
        let ordinary = try XCTUnwrap(txns.first { $0.entryId == ordinaryId })
        XCTAssertEqual(ordinary.accountLegCount, 1)
        XCTAssertNotEqual(ordinary.entryId, ordinary.id)

        XCTAssertTrue(txns.allSatisfy { $0.entryId != nil }, "every projected row carries an entryId")

        // What this buys: counting purchases instead of payment legs.
        XCTAssertEqual(txns.count, 3, "three feed rows")
        XCTAssertEqual(Set(txns.compactMap(\.entryId)).count, 2, "but only two purchases")
    }
}
