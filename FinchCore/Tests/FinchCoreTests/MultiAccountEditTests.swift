import XCTest
import GRDB
@testable import FinchCore

final class MultiAccountEditTests: XCTestCase {

    private func splitPurchase() throws -> (DatabaseQueue, String) {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"),
            "accounts": .array([
                .object(["accountId": .string("a2"), "amount": .double(-60)]),
                .object(["accountId": .string("a1"), "amount": .double(-40)]),
            ])]))
        return (q, eid!)
    }

    /// Renaming the merchant touches no money and must succeed.
    func test_headerOnlyPatch_onSplitPurchase_succeeds() throws {
        let (q, eid) = try splitPurchase()
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(eid), "patch": .object(["merchant": .string("Waitrose")])]))
        let name = try q.read { db in
            try String.fetchOne(db, sql: "SELECT description FROM entries WHERE id = ?", arguments: [eid])
        }
        XCTAssertEqual(name, "Waitrose")
    }

    /// A money patch is still refused — but with the SPLIT message, not the transfer one.
    func test_moneyPatch_onSplitPurchase_throwsSplitMessage() throws {
        let (q, eid) = try splitPurchase()
        do {
            try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
                "id": .string(eid), "patch": .object(["amount": .double(-120)])]))
            XCTFail("editing the money of a split purchase should be refused")
        } catch let e as I18nError {
            XCTAssertEqual(e.code, "error.tx.splitLegEdit",
                           "a split purchase is not a transfer — don't send its user to the Transfers screen")
        }
    }

    /// A real transfer keeps the transfer message.
    func test_moneyPatch_onTransfer_stillThrowsTransferMessage() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-02", time: "09:00",
                description: "Move", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -50)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 50)),
                ]))
        }
        do {
            try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
                "id": .string(eid), "patch": .object(["amount": .double(-70)])]))
            XCTFail("editing a transfer's money through updateTransaction should be refused")
        } catch let e as I18nError {
            XCTAssertEqual(e.code, "error.tx.transferLegEdit")
        }
    }

    // MARK: updateTransfer — the fifth unguarded-rebuild site (final review, Fix 1)
    //
    // Transfers.update selects ALL account legs, picks fromLeg = first(amount<0)
    // ?? legs[0] and toLeg = first(amount>0) ?? legs[last], then replaces the
    // entry's ENTIRE leg set with just those two. Its only precondition was
    // legs.count >= 2, which a split purchase now satisfies — so calling
    // updateTransfer on a split purchase would drop the category leg and any
    // account leg beyond two. Refuse it the same way updateTransaction does.

    /// A split purchase routed through updateTransfer (e.g. a stale/guessed
    /// group id) must be refused with the split message, not silently rebuilt.
    func test_updateTransfer_onSplitPurchase_throwsSplitMessage() throws {
        let (q, eid) = try splitPurchase()
        do {
            try Apply.apply(dbQueue: q, action: "updateTransfer", args: Args([
                "id": .string(eid), "patch": .object(["fromAmount": .double(50)])]))
            XCTFail("editing a split purchase through updateTransfer should be refused")
        } catch let e as I18nError {
            XCTAssertEqual(e.code, "error.tx.splitLegEdit",
                           "a split purchase is not a transfer — don't silently rebuild its legs")
        }
        // The refusal must leave the entry exactly as it was.
        let legs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [eid])
        }
        XCTAssertEqual(legs, 2, "both payment accounts must survive the refusal")
    }

    /// A genuine transfer must keep updating successfully through updateTransfer.
    func test_updateTransfer_onGenuineTransfer_succeeds() throws {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
        }
        let eid = try q.write { db in
            try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: "l1", date: "2026-06-02", time: "09:00",
                description: "Move", kind: .transfer,
                legs: [
                    .account(Entries.AccountLeg(accountId: "a1", amount: -50)),
                    .account(Entries.AccountLeg(accountId: "a2", amount: 50)),
                ]))
        }
        try Apply.apply(dbQueue: q, action: "updateTransfer", args: Args([
            "id": .string(eid), "patch": .object(["fromAmount": .double(80)])]))
        let (fromBal, toBal) = try q.read { db in
            (try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? 0,
             try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? 0)
        }
        XCTAssertEqual(fromBal, -80, accuracy: 0.001, "a genuine transfer must still update")
        XCTAssertEqual(toBal, 80, accuracy: 0.001)
    }
}
