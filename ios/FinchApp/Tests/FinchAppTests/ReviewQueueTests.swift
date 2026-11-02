import XCTest
@testable import FinchApp
import FinchCore
import GRDB

/// `ReviewQueue` — which rows Activity's review queue holds, how it is counted, and
/// that "Mark all reviewed" touches exactly the rows it was handed.
final class ReviewQueueTests: XCTestCase {
    private func tx(_ id: String, pending: Bool? = nil, reviewedAt: String? = nil,
                    ledgerId: String? = "personal", entryId: String? = nil,
                    amount: Double = -10, account: String = "a") -> Tx {
        var t = Tx(id: id, merchant: "m", amount: amount, account: account, date: "2026-09-01",
                   pending: pending, ledgerId: ledgerId, reviewedAt: reviewedAt)
        t.entryId = entryId
        return t
    }

    /// Both rows of one transfer: the leg that left `from`, the leg that reached `to`.
    /// Same entry — reviewing either reviews both.
    private func transfer(_ entry: String, from: String = "chk", to: String = "sav") -> [Tx] {
        var out = tx("\(entry)-in", entryId: entry, amount: 500, account: to)
        out.kind = "transfer"
        var leg = tx("\(entry)-out", entryId: entry, amount: -500, account: from)
        leg.kind = "transfer"
        // Incoming first, so "keeps the outgoing leg" is not just "keeps the first".
        return [out, leg]
    }

    // MARK: Membership

    func test_needsReview_is_settled_and_unreviewed() {
        XCTAssertTrue(ReviewQueue.needsReview(tx("1")))
        XCTAssertTrue(ReviewQueue.needsReview(tx("1", pending: false)))
        XCTAssertFalse(ReviewQueue.needsReview(tx("1", reviewedAt: "2026-09-02 10:00:00")))
    }

    /// A pending row is waiting in "To confirm" already. Putting it here too would
    /// make the two queues read as one, and reviewing it would not confirm it.
    func test_pending_rows_are_never_in_the_queue() {
        XCTAssertFalse(ReviewQueue.needsReview(tx("1", pending: true)))
        XCTAssertFalse(ReviewQueue.needsReview(tx("1", pending: true, reviewedAt: "2026-09-02")))
    }

    // MARK: Filtering

    func test_listStatus_sends_the_queue_to_the_engine_as_confirmed() {
        XCTAssertEqual(ReviewQueue.listStatus(ReviewQueue.status), "confirmed")
        // Every other status passes through untouched.
        XCTAssertNil(ReviewQueue.listStatus(nil))
        XCTAssertEqual(ReviewQueue.listStatus("pending"), "pending")
        XCTAssertEqual(ReviewQueue.listStatus("confirmed"), "confirmed")
    }

    func test_narrow_keeps_only_unreviewed_and_preserves_order() {
        let input = [tx("3"), tx("2", reviewedAt: "x"), tx("1"), tx("0", pending: true)]
        XCTAssertEqual(ReviewQueue.narrow(input, status: ReviewQueue.status).map(\.id), ["3", "1"])
    }

    func test_narrow_is_a_noop_outside_the_queue() {
        let input = [tx("3"), tx("2", reviewedAt: "x"), tx("0", pending: true)]
        for status in [nil, "pending", "confirmed"] {
            XCTAssertEqual(ReviewQueue.narrow(input, status: status).map(\.id), ["3", "2", "0"], "\(status ?? "nil")")
        }
    }

    /// The queue composes with the existing pipeline: the engine's confirmed filter
    /// runs first, then `narrow`. The same two steps both feeds take.
    func test_queue_through_the_engine_selector() {
        let input = [tx("a"), tx("b", reviewedAt: "x"), tx("c", pending: true), tx("d")]
        let opts = ListOptions(ledgerId: "personal", status: ReviewQueue.listStatus(ReviewQueue.status))
        let out = ReviewQueue.narrow(Selectors.selectTransactions(input, opts), status: ReviewQueue.status)
        XCTAssertEqual(Set(out.map(\.id)), ["a", "d"])
    }

    // MARK: Count

    func test_count_is_per_ledger_and_ignores_reviewed_and_pending() {
        let input = [tx("1"), tx("2"), tx("3", reviewedAt: "x"), tx("4", pending: true),
                     tx("5", ledgerId: "travel"),
                     tx("6", ledgerId: nil)]   // a nil ledger is the personal one, as on the web
        XCTAssertEqual(ReviewQueue.count(input, ledgerId: "personal"), 3)
        XCTAssertEqual(ReviewQueue.count(input, ledgerId: "travel"), 1)
        XCTAssertEqual(ReviewQueue.count([], ledgerId: "personal"), 0)
    }

    /// A transfer is ONE entry with two rows. Six of them used to read "12 to
    /// review"; reviewing is per entry, so the count is too.
    func test_count_is_per_entry_not_per_row() {
        let six = (1...6).flatMap { transfer("t\($0)") }
        XCTAssertEqual(six.count, 12)
        XCTAssertEqual(ReviewQueue.count(six, ledgerId: "personal"), 6)
        // A purchase paid from two cards is one entry too.
        let split = [tx("p1", entryId: "e1", account: "visa"), tx("p2", entryId: "e1", account: "amex")]
        XCTAssertEqual(ReviewQueue.count(split + [tx("solo")], ledgerId: "personal"), 2)
    }

    /// The queue lists each entry once, so the rows and the count say the same
    /// number. A transfer keeps the leg money left from ("To Savings").
    func test_queue_lists_each_entry_once_keeping_the_outgoing_leg() {
        let input = [tx("a")] + transfer("t1") + [tx("b")]
        let rows = ReviewQueue.narrow(input, status: ReviewQueue.status)
        XCTAssertEqual(rows.map(\.id), ["a", "t1-out", "b"])
        XCTAssertEqual(rows.count, ReviewQueue.count(input, ledgerId: "personal"))
    }

    /// Outside the queue nothing collapses: the feed still shows both legs.
    func test_only_the_queue_collapses_legs() {
        let input = transfer("t1")
        XCTAssertEqual(ReviewQueue.narrow(input, status: nil).map(\.id), ["t1-in", "t1-out"])
    }

    /// Filtered to one account, the transfer shows the leg that is there.
    func test_a_filtered_queue_keeps_the_leg_it_has() {
        let savingsOnly = transfer("t1").filter { $0.account == "sav" }
        XCTAssertEqual(ReviewQueue.narrow(savingsOnly, status: ReviewQueue.status).map(\.id), ["t1-in"])
    }

    // MARK: Confirmation

    func test_mark_all_asks_from_the_threshold_up() {
        XCTAssertFalse(ReviewQueue.needsConfirmation(1))
        XCTAssertFalse(ReviewQueue.needsConfirmation(ReviewQueue.confirmationThreshold - 1))
        XCTAssertTrue(ReviewQueue.needsConfirmation(ReviewQueue.confirmationThreshold))
        XCTAssertTrue(ReviewQueue.needsConfirmation(500))
    }

    // MARK: The write

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: name, withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
    }

    /// Through the real chokepoint: the rows passed leave the queue, every other
    /// unreviewed row stays in it. The ledger-wide `markAllReviewed` would fail the
    /// second half — which is why the queue does not call it.
    @MainActor
    func test_markReviewed_stamps_exactly_the_rows_passed() async throws {
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: fixture("sample")))
        let ledger = store.activeLedgerId
        let queue = store.txns.filter { ($0.ledgerId ?? "personal") == ledger && ReviewQueue.needsReview($0) }
        try XCTSkipIf(queue.count < 3, "fixture needs at least three unreviewed rows")

        // Whole purchases, so a sibling leg leaving with its row cannot blur the count.
        let picked = Set(queue.prefix(2).map(\.purchaseKey))
        let rows = queue.filter { picked.contains($0.purchaseKey) }
        let ids = rows.map(\.id)
        let entries = Set(rows.map { $0.entryId ?? $0.id })
        let before = ReviewQueue.count(store.txns, ledgerId: ledger)

        XCTAssertEqual(store.markReviewed(ids), ids.count)

        let after = store.txns.filter { ids.contains($0.id) }
        XCTAssertTrue(after.allSatisfy { $0.reviewedAt != nil }, "every passed row is stamped")
        // The count is per entry, so it drops by the entries the rows belong to.
        XCTAssertEqual(ReviewQueue.count(store.txns, ledgerId: ledger), before - entries.count,
                       "nothing outside the passed rows left the queue")
    }

    // MARK: After the update

    /// Restoring a backup an iOS build made before the review queue existed brings
    /// back no backlog: `loadPack` migrates the staged copy, and the one-time clear
    /// (`Migrations.clearReviewBacklog`) runs on it like on the live database.
    ///
    /// The sample fixture is a WEB pack — the web has had its queue all along, so
    /// it keeps its unreviewed rows (the test above depends on that). Opening it
    /// once with the migrator, minus the clear's record, makes it the database an
    /// older iOS build would have exported.
    /// Synchronous on purpose: inside an async test GRDB's `write` resolves to its
    /// async overload.
    private func makePreUpdateIOSDatabase(_ url: URL) throws {
        let q = try DatabaseQueue(path: url.path)
        try Migrations.runAll(on: q)
        // An older iOS build's bookkeeping: every migration but the clear.
        try q.write { try $0.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = '2026-11-02-review-backlog'") }
        try q.close()
    }

    @MainActor
    func test_restoring_a_pre_update_backup_brings_no_backlog() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rq-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let extracted = try Pack.extract(try Pack.parse(try Data(contentsOf: fixture("sample"))),
                                         to: dir.appendingPathComponent("old"))
        try makePreUpdateIOSDatabase(extracted.dbPath)
        let pack = try Pack.build(.init(
            dbBytes: try Data(contentsOf: extracted.dbPath),
            meta: .init(appVersion: "1", schemaVersion: Schema.version, exportedAt: "2026-10-30T00:00:00Z",
                        exportedFrom: nil, rowCounts: [:])))

        let store = FinchStore()
        try await store.loadPack(from: pack.bytes)
        XCTAssertFalse(store.txns.isEmpty)
        XCTAssertTrue(store.txns.allSatisfy { $0.pending == true || $0.reviewedAt != nil })
        XCTAssertEqual(ReviewQueue.count(store.txns, ledgerId: store.activeLedgerId), 0)
    }

    @MainActor
    func test_markReviewed_empty_is_a_noop() {
        XCTAssertEqual(FinchStore().markReviewed([]), 0)
    }
}
