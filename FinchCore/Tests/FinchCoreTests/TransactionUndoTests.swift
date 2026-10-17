import XCTest
import GRDB
@testable import FinchCore

/// Undo of a transaction delete — `TransactionUndo.capture` → `deleteTransaction`
/// → `settle` → `restoreTransactions`.
///
/// The bar is "as if the delete never happened": every test compares a dump of
/// EVERY table (raw columns, rowids included, the FTS mirror too) and the
/// projected `[Tx]` before the delete with the same after the restore. A field
/// comparison would pass while an iOS-only column — `group_id`, a refund link on
/// another row — silently stayed cleared.
///
/// Native-only, so not in the web parity fixtures; `ParityTests` adds one
/// round trip over the oracle's own write sequence.
final class TransactionUndoTests: XCTestCase {

    // MARK: fixtures

    private func seeded() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,created_at,updated_at) VALUES ('t1','l1','Trip',datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO tags (id,ledger_id,name,created_at,updated_at) VALUES ('t2','l1','Work',datetime('now'),datetime('now'))")
        }
        return q
    }

    @discardableResult
    private func add(_ q: DatabaseQueue, amount: Double = -25, account: String = "a1", merchant: String = "Coffee",
                     date: String = "2026-05-01", extra: [String: JSONValue] = [:]) throws -> String {
        var o: [String: JSONValue] = [
            "ledgerId": .string("l1"), "accountId": .string(account), "amount": .double(amount),
            "merchant": .string(merchant), "categoryId": .string("c1"), "date": .string(date),
            "time": .string("09:30"), "skipRules": .bool(true)]
        for (k, v) in extra { o[k] = v }
        return try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args(o))!
    }

    /// The Tx id the UI holds for an entry: its first account-leg posting.
    private func txId(_ q: DatabaseQueue, _ entryId: String) throws -> String {
        try q.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order LIMIT 1",
                                arguments: [entryId])!
        }
    }

    private func attach(_ q: DatabaseQueue, _ entryId: String, id: String = "att-1") throws {
        try Apply.apply(dbQueue: q, action: "setEntryAttachment", args: Args([
            "id": .string(id), "entryId": .string(entryId), "kind": .string("image"),
            "relPath": .string("attachments/\(entryId)/\(id).jpg"), "mimeType": .string("image/jpeg"),
            "byteSize": .double(1234), "sha256": .string("abc")]))
    }

    /// Every table, every column, rowid included — the strictest "same database"
    /// there is short of comparing files. FTS shadow tables are skipped; the FTS
    /// table itself is dumped by content (its rowid is internal to FTS).
    private func dump(_ q: DatabaseQueue) throws -> [String: [[String: String]]] {
        try q.read { db in
            var out: [String: [[String: String]]] = [:]
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table'
                 AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'entries_fts%' ORDER BY name
                """)
            func rows(_ sql: String) throws -> [[String: String]] {
                try Row.fetchAll(db, sql: sql).map { r in
                    var o: [String: String] = [:]
                    for (c, v) in r { o[c] = v.isNull ? "NULL" : "\(v)" }
                    return o
                }
            }
            for t in tables { out[t] = try rows("SELECT rowid AS _rowid, * FROM \"\(t)\" ORDER BY rowid") }
            out["entries_fts"] = try rows("SELECT id, description, notes FROM entries_fts ORDER BY id")
            return out
        }
    }

    private func assertSameDB(_ a: [String: [[String: String]]], _ b: [String: [[String: String]]],
                              file: StaticString = #filePath, line: UInt = #line) {
        for t in Set(a.keys).union(b.keys).sorted() where a[t] != b[t] {
            XCTFail("table \(t) differs:\n  before: \(a[t] ?? [])\n  after:  \(b[t] ?? [])", file: file, line: line)
        }
    }

    /// Delete `ids` exactly as `FinchStore.deleteTransactions` does, then return the
    /// settled snapshot — pushed through a JSON encode/decode, which is what a
    /// sync replay would do to it, so number types must survive the trip.
    private func delete(_ q: DatabaseQueue, _ ids: [String]) throws -> Args {
        let captured = try q.read { try TransactionUndo.capture($0, txIds: ids) }
        for id in ids { try? Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(id)])) }
        let settled = try q.read { try TransactionUndo.settle(captured, $0) }
        let wire = try JSONEncoder().encode(try settled.args)
        return try JSONDecoder().decode(Args.self, from: wire)
    }

    private func restore(_ q: DatabaseQueue, _ args: Args) throws {
        try Apply.apply(dbQueue: q, action: "restoreTransactions", args: args)
    }

    /// The full round trip: state before == state after restore, by dump AND by
    /// projection, and the delete really did remove something.
    private func assertRoundTrip(_ q: DatabaseQueue, _ ids: [String],
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        // Every write so far stamped "now" at one-second resolution, and so will
        // the delete's recompute — so an un-restored timestamp would match by luck.
        // An old stamp makes it a real difference.
        try q.write { db in try db.execute(sql: "UPDATE accounts SET updated_at = '2026-01-01T00:00:00Z'") }
        let before = try dump(q)
        let txBefore = try Projection.run(dbQueue: q, ledgerId: "l1")
        let auditBefore = try Audit.run(on: q).count
        let args = try delete(q, ids)
        XCTAssertNotEqual(try dump(q), before, "the delete must have removed something", file: file, line: line)
        try restore(q, args)
        assertSameDB(before, try dump(q), file: file, line: line)
        XCTAssertEqual(try Projection.run(dbQueue: q, ledgerId: "l1"), txBefore, file: file, line: line)
        XCTAssertEqual(try Audit.run(on: q).count, auditBefore, file: file, line: line)
    }

    // MARK: round trips

    /// The plain case, with everything that hangs off an entry: tags, a receipt,
    /// a merchant, a note, a cleared leg.
    func test_expenseWithTagsAndReceipt_roundTrips() throws {
        let q = try seeded()
        let eid = try add(q, extra: ["tagIds": .array([.string("t1"), .string("t2")]), "note": .string("latte")])
        try attach(q, eid)
        let tx = try txId(q, eid)
        try Apply.apply(dbQueue: q, action: "setCleared", args: Args(["id": .string(tx), "cleared": .bool(true)]))
        try add(q, amount: -9, merchant: "Bakery")   // an unrelated survivor
        try assertRoundTrip(q, [tx])
    }

    /// The restored receipt row keeps its id — the app's file path and any
    /// open preview name it.
    func test_attachmentKeepsItsId() throws {
        let q = try seeded()
        let eid = try add(q)
        try attach(q, eid, id: "att-keep")
        let args = try delete(q, [try txId(q, eid)])
        try restore(q, args)
        let ids = try q.read { db in try String.fetchAll(db, sql: "SELECT id FROM entry_attachments") }
        XCTAssertEqual(ids, ["att-keep"])
    }

    /// A transfer is one entry with two account legs; both come back, and both
    /// balances return to what they were.
    func test_transfer_roundTrips() throws {
        let q = try seeded()
        try add(q, amount: 500, merchant: "Salary", extra: ["kind": .string("income")])
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"),
            "fromAmount": .double(120), "date": .string("2026-05-03")]))
        let tx = try q.read { db in
            try String.fetchOne(db, sql: "SELECT p.id FROM postings p JOIN entries e ON e.id = p.entry_id WHERE e.kind = 'transfer' AND p.account_id = 'a2'")!
        }
        try assertRoundTrip(q, [tx])
    }

    /// Two cards, one category: one entry with two payment legs. Deleting by EITHER
    /// leg's id takes the whole purchase, and the restore brings back both.
    func test_splitTender_roundTripsFromEitherLeg() throws {
        let q = try seeded()
        let eid = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "date": .string("2026-06-01"), "time": .string("12:00"),
            "merchant": .string("Market"), "kind": .string("expense"), "currency": .string("USD"),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-60)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c1"), "amount": .double(-40)]),
            ])]))!
        let secondLeg = try q.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM postings WHERE entry_id = ? AND account_id = 'a2'", arguments: [eid])!
        }
        try assertRoundTrip(q, [secondLeg])
    }

    /// A category split: one account leg, several category legs, with memos.
    func test_categorySplit_roundTrips() throws {
        let q = try seeded()
        let eid = try Apply.applyReturningId(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "date": .string("2026-06-01"), "time": .string("12:00"),
            "merchant": .string("Market"), "kind": .string("expense"), "currency": .string("USD"),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-30), "memo": .string("food")]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-12.34)]),
            ])]))!
        try assertRoundTrip(q, [try txId(q, eid)])
    }

    /// Deleting a purchase clears the link on the refund that points at it
    /// (`ON DELETE SET NULL`, on a row nobody selected). Undo must put it back.
    func test_refundOfADeletedPurchase_getsItsLinkBack() throws {
        let q = try seeded()
        let purchase = try add(q, amount: -80, merchant: "Store")
        let refund = try add(q, amount: 30, merchant: "Store", date: "2026-05-05",
                             extra: ["kind": .string("refund"), "refundedTransactionId": .string(purchase)])
        let args = try delete(q, [try txId(q, purchase)])
        XCTAssertNil(try q.read { db in try String.fetchOne(db, sql: "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [refund]) },
                     "precondition: the delete cleared the survivor's link")
        try restore(q, args)
        XCTAssertEqual(try q.read { db in try String.fetchOne(db, sql: "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [refund]) },
                       purchase)
    }

    /// Both ends of a refund link deleted together — the link lives INSIDE the
    /// restore, and must survive insertion order.
    func test_purchaseAndItsRefundTogether_roundTrip() throws {
        let q = try seeded()
        let purchase = try add(q, amount: -80, merchant: "Store")
        let refund = try add(q, amount: 30, merchant: "Store", date: "2026-05-05",
                             extra: ["kind": .string("refund"), "refundedTransactionId": .string(purchase)])
        // Refund FIRST, so the restore meets the referencing row before its target.
        try assertRoundTrip(q, [try txId(q, refund), try txId(q, purchase)])
        try assertRoundTrip(q, [try txId(q, purchase), try txId(q, refund)])
    }

    /// A grid purchase (two cards × two categories) is two entries sharing a
    /// group. Deleting one leaves a group of one, which the engine dissolves — on
    /// the survivor, a row nobody touched. Undo must re-form the group.
    func test_gridMember_restoreReformsTheGroup() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "date": .string("2026-06-01"), "time": .string("12:00"),
            "merchant": .string("Market"), "kind": .string("expense"), "currency": .string("USD"),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-40)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-20)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c1"), "amount": .double(-30)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c2"), "amount": .double(-10)]),
            ])]))
        let members = try q.read { db in try String.fetchAll(db, sql: "SELECT id FROM entries WHERE group_id IS NOT NULL ORDER BY id") }
        XCTAssertEqual(members.count, 2, "precondition: a grid is two grouped entries")
        try assertRoundTrip(q, [try txId(q, members[0])])
    }

    /// Deleting a pending transaction and bringing it back keeps it pending.
    func test_pending_roundTrips() throws {
        let q = try seeded()
        let eid = try add(q, extra: ["status": .string("pending")])
        try assertRoundTrip(q, [try txId(q, eid)])
    }

    /// A bulk delete is one undo for the lot.
    func test_bulk_roundTrips() throws {
        let q = try seeded()
        let ids = try (0..<5).map { i in try txId(q, try add(q, amount: Double(-(i + 1)), merchant: "M\(i)",
                                                             date: "2026-05-0\(i + 1)")) }
        try add(q, amount: -3, merchant: "Survivor")
        try assertRoundTrip(q, ids)
    }

    /// A rolled budget's cache is reset by a delete in a rolled period; undoing
    /// the delete makes the old cache true again, so it comes back too.
    func test_budgetRolloverInvalidatedByTheDelete_isRestored() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "ledgerId": .string("l1"), "name": .string("Food"), "kind": .string("expense"), "amount": .double(300),
            "frequency": .string("monthly"), "startDate": .string("2026-01-01"), "categoryIds": .array([.string("c1")])]))
        let eid = try add(q, date: "2026-03-10")
        try q.write { db in
            try db.execute(sql: "UPDATE budgets SET last_rolled_period = '2026-05-01', carry_forward = 42, updated_at = '2026-06-01T00:00:00Z'")
        }
        try assertRoundTrip(q, [try txId(q, eid)])
    }

    /// Ids that do not resolve capture nothing and restore nothing.
    func test_unknownIds_captureNothing() throws {
        let q = try seeded()
        let snap = try q.read { try TransactionUndo.capture($0, txIds: ["nope"]) }
        XCTAssertTrue(snap.isEmpty)
    }

    /// `settle` keeps only what really went: an entry captured but not deleted
    /// (an op the batch skipped) must not be "restored" over itself.
    func test_settle_dropsWhatTheDeleteDidNotTake() throws {
        let q = try seeded()
        let keep = try txId(q, try add(q, merchant: "Kept"))
        let gone = try txId(q, try add(q, merchant: "Gone", date: "2026-05-02"))
        let captured = try q.read { try TransactionUndo.capture($0, txIds: [keep, gone]) }
        XCTAssertEqual(captured.entries.count, 2)
        try Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(gone)]))
        let settled = try q.read { try TransactionUndo.settle(captured, $0) }
        XCTAssertEqual(settled.entries.count, 1)
        XCTAssertEqual(settled.postings.count, 2)
        try restore(q, try settled.args)
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind != 'opening'") }, 2)
    }

    /// Attachment paths are exposed so the app knows which files to keep.
    func test_attachmentRelPaths() throws {
        let q = try seeded()
        let eid = try add(q)
        try attach(q, eid, id: "att-x")
        let tx = try txId(q, eid)
        let snap = try q.read { try TransactionUndo.capture($0, txIds: [tx]) }
        XCTAssertEqual(snap.attachmentRelPaths, ["attachments/\(eid)/att-x.jpg"])
    }

    // MARK: staleness — refuse, and write nothing

    /// The second undo of the same delete: every id is taken again.
    func test_restoringTwice_isRefused() throws {
        let q = try seeded()
        let args = try delete(q, [try txId(q, try add(q))])
        try restore(q, args)
        let after = try dump(q)
        XCTAssertThrowsError(try restore(q, args)) { XCTAssertEqual(($0 as? I18nError)?.code, "error.undo.stale") }
        assertSameDB(after, try dump(q))
    }

    /// Something the restore needs went away in between (a tag deleted): refuse
    /// as a whole — no half-restored transaction without its tag.
    func test_aMissingReference_refusesAndWritesNothing() throws {
        let q = try seeded()
        let args = try delete(q, [try txId(q, try add(q, extra: ["tagIds": .array([.string("t1")])]))])
        try Apply.apply(dbQueue: q, action: "deleteTag", args: Args(["id": .string("t1")]))
        let before = try dump(q)
        XCTAssertThrowsError(try restore(q, args)) { XCTAssertEqual(($0 as? I18nError)?.code, "error.undo.stale") }
        assertSameDB(before, try dump(q))
    }

    /// A snapshot naming a column the table does not have is refused rather than
    /// spliced into SQL.
    func test_unknownColumn_isRefused() throws {
        let q = try seeded()
        let args = try delete(q, [try txId(q, try add(q))])
        guard case .array(var entries)? = args.values["entries"], case .object(var e) = entries[0] else { return XCTFail() }
        e["bogus\"; DROP TABLE entries; --"] = .string("x")
        entries[0] = .object(e)
        var v = args.values; v["entries"] = .array(entries)
        XCTAssertThrowsError(try restore(q, Args(v))) { XCTAssertEqual(($0 as? I18nError)?.code, "error.undo.stale") }
        XCTAssertNotNil(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries") })
    }
}

/// The cross-ledger case on its own fixture: two ledgers, two bases.
final class InterledgerUndoTests: XCTestCase {
    func test_deletingOneHalf_restoresBoth() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('personal','Personal','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('travel','Travel','EUR',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('checking','personal','Checking','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('card','travel','Travel Card','credit_card','EUR',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-08-12','EUR',1.10)")
            try Entries.postOpening(db, ledgerId: "personal", accountId: "checking", amount: 12000, date: "2026-01-01")
        }
        try Apply.apply(dbQueue: q, action: "createInterledgerTransfer", args: Args([
            "fromAccountId": .string("checking"), "toAccountId": .string("card"),
            "fromAmount": .double(5000), "toAmount": .double(4600), "date": .string("2026-08-12")]))
        let personalTx = try q.read { db in
            try String.fetchOne(db, sql: "SELECT p.id FROM postings p JOIN entries e ON e.id = p.entry_id WHERE e.kind = 'interledger' AND p.account_id = 'checking'")!
        }
        let balances = { try q.read { db in try Row.fetchAll(db, sql: "SELECT id, current_balance FROM accounts ORDER BY id").map { "\($0)" } } }
        let before = try balances()
        let txBefore = try Projection.run(dbQueue: q)

        let captured = try q.read { try TransactionUndo.capture($0, txIds: [personalTx]) }
        XCTAssertEqual(captured.entries.count, 2, "the capture follows the link into the other ledger")
        try Apply.apply(dbQueue: q, action: "deleteTransaction", args: Args(["id": .string(personalTx)]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind = 'interledger'") }, 0)
        let settled = try q.read { try TransactionUndo.settle(captured, $0) }
        try Apply.apply(dbQueue: q, action: "restoreTransactions", args: try settled.args)

        XCTAssertEqual(try balances(), before)
        XCTAssertEqual(try Projection.run(dbQueue: q), txBefore)
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT interledger_link_id) FROM entries WHERE kind = 'interledger'") }, 1)
        XCTAssertTrue(try Audit.run(on: q).isEmpty, "both books are true again")
    }
}
