import XCTest
import GRDB
@testable import FinchCore

/// `entries.pending_kind` is a CACHE of one rule — a pending row dated after today is
/// `upcoming`, otherwise `due`. Because the rule's answer changes at midnight without
/// anything touching the row, the only thing worth testing is the invariant:
///
///     after a refresh, every row's stored kind == what the rule says for that day
///
/// A cache that can disagree with its rule is worse than no cache, so that is asserted
/// exhaustively rather than case by case.
final class PendingKindTests: XCTestCase {

    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        }
        return q
    }

    /// One entry AND its account posting. Left UNSEALED: postings may only be written
    /// while `sealed = 0` (the seal trigger rejects them otherwise), and nothing these
    /// tests touch — the projection included — filters on `sealed`.
    ///
    /// The posting is not optional garnish:
    /// `Projection.run` joins postings, so an entry without one never appears in a
    /// projection — and a test that reads the projection would iterate an empty list
    /// and pass without asserting anything.
    private func add(_ q: DatabaseQueue, _ id: String, _ date: String, _ status: String) throws {
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at)
                VALUES (?,'l1',?,'x','expense',?,0,datetime('now'),datetime('now'))
                """, arguments: [id, date, status])
            try db.execute(sql: """
                INSERT INTO postings (id,entry_id,account_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES (?,?,'a1',-5,'USD',-5,1,0)
                """, arguments: ["p-" + id, id])
        }
    }

    private func kind(_ q: DatabaseQueue, _ id: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT pending_kind FROM entries WHERE id = ?", arguments: [id]) }
    }

    /// The invariant, over every combination that matters.
    func test_afterRefreshTheStoredKindMatchesTheRule() throws {
        let q = try seeded()
        let today = "2026-05-10"
        let rows: [(id: String, date: String, status: String, expected: String?)] = [
            ("past-pending",   "2026-05-01", "pending",   "due"),
            ("today-pending",  "2026-05-10", "pending",   "due"),      // today is DUE, not upcoming
            ("future-pending", "2026-05-11", "pending",   "upcoming"),
            ("past-conf",      "2026-05-01", "confirmed", nil),
            ("future-conf",    "2026-05-11", "confirmed", nil),        // confirmed early: no kind
        ]
        for r in rows { try add(q, r.id, r.date, r.status) }
        try q.write { db in _ = try Entries.refreshPendingKind(db, today: today) }
        for r in rows {
            XCTAssertEqual(try kind(q, r.id), r.expected, "\(r.id)")
        }
    }

    /// The whole reason the refresh is bidirectional: the same rows, a later day.
    func test_theSameRowsFlipWhenTheDayMoves() throws {
        let q = try seeded()
        try add(q, "rent", "2026-06-01", "pending")
        try q.write { db in _ = try Entries.refreshPendingKind(db, today: "2026-05-31") }
        XCTAssertEqual(try kind(q, "rent"), "upcoming")

        try q.write { db in _ = try Entries.refreshPendingKind(db, today: "2026-06-01") }
        XCTAssertEqual(try kind(q, "rent"), "due", "the day arrived; nothing touched the row")
    }

    /// The impossible state this column exists to prevent. Editing a date backwards or
    /// forwards must not be able to leave "pending, dated next month" marked due.
    func test_aRowEditedIntoTheFutureIsCorrectedBack() throws {
        let q = try seeded()
        try add(q, "e1", "2026-05-01", "pending")
        try q.write { db in _ = try Entries.refreshPendingKind(db, today: "2026-05-10") }
        XCTAssertEqual(try kind(q, "e1"), "due")

        // The user corrects the date to next month; the refresh runs after the write.
        try q.write { db in
            try db.execute(sql: "UPDATE entries SET date = '2026-06-15' WHERE id = 'e1'")
            _ = try Entries.refreshPendingKind(db, today: "2026-05-10")
        }
        XCTAssertEqual(try kind(q, "e1"), "upcoming", "pending + future must never stay 'due'")
    }

    /// Confirming clears the kind rather than leaving a stale one behind.
    func test_confirmingClearsTheKind() throws {
        let q = try seeded()
        try add(q, "e1", "2026-05-01", "pending")
        try q.write { db in _ = try Entries.refreshPendingKind(db, today: "2026-05-10") }
        XCTAssertEqual(try kind(q, "e1"), "due")

        try q.write { db in
            try db.execute(sql: "UPDATE entries SET status = 'confirmed' WHERE id = 'e1'")
            _ = try Entries.refreshPendingKind(db, today: "2026-05-10")
        }
        XCTAssertNil(try kind(q, "e1"))
    }

    /// The refresh is run constantly, so it must be cheap and quiet when nothing moved:
    /// a second run writes no rows. Without the `IS NOT` guards every run would rewrite
    /// every pending row, and `updated_at` churn would look like edits to sync.
    func test_aSecondRefreshChangesNothing() throws {
        let q = try seeded()
        try add(q, "a", "2026-05-01", "pending")
        try add(q, "b", "2026-06-01", "pending")
        try add(q, "c", "2026-05-01", "confirmed")
        let first = try q.write { db in try Entries.refreshPendingKind(db, today: "2026-05-10") }
        XCTAssertEqual(first, 2, "two pending rows needed a kind")
        let second = try q.write { db in try Entries.refreshPendingKind(db, today: "2026-05-10") }
        XCTAssertEqual(second, 0, "an idempotent refresh must write nothing the second time")
    }

    /// The column has to reach the APP, not just sit in the database. This test exists
    /// because the projection mapping was missed on the first pass and every other test
    /// still passed — they all read SQL directly, so nothing noticed that `Tx.pendingKind`
    /// was always nil.
    func test_theKindReachesTheProjectedTx() throws {
        let q = try seeded()
        try add(q, "e1", "2026-06-01", "pending")
        try q.write { db in _ = try Entries.refreshPendingKind(db, today: "2026-05-10") }
        // Tx is at per-leg grain: `id` is the POSTING id, the entry is `entryId`.
        let tx = try XCTUnwrap(Projection.run(dbQueue: q, ledgerId: "l1").first { $0.entryId == "e1" })
        XCTAssertEqual(tx.pendingKind, "upcoming", "the projection must carry the column through")
        XCTAssertEqual(tx.pending, true, "and an upcoming row is still pending")
    }

    /// It agrees with the selector the screens already use, which is the definition of
    /// record. If these two ever disagree the cache is lying.
    func test_itAgreesWithPendingSplit() throws {
        let today = "2026-05-10"
        let q = try seeded()
        for (i, d) in ["2026-05-01", "2026-05-10", "2026-05-11", "2026-12-31"].enumerated() {
            try add(q, "e\(i)", d, "pending")
        }
        try q.write { db in _ = try Entries.refreshPendingKind(db, today: today) }

        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        XCTAssertEqual(txns.count, 4, "guard against a vacuous pass: no rows means the loops below assert nothing")
        let split = Selectors.pendingSplit(txns, today: today)
        XCTAssertFalse(split.upcoming.isEmpty)
        XCTAssertFalse(split.dueNow.isEmpty)
        for t in split.upcoming { XCTAssertEqual(try kind(q, t.entryId ?? ""), "upcoming", t.entryId ?? "?") }
        for t in split.dueNow  { XCTAssertEqual(try kind(q, t.entryId ?? ""), "due", t.entryId ?? "?") }
    }
}
