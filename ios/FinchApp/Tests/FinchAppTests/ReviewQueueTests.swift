import XCTest
@testable import FinchApp
import FinchCore

/// `ReviewQueue` — which rows Activity's review queue holds, how it is counted, and
/// that "Mark all reviewed" touches exactly the rows it was handed.
final class ReviewQueueTests: XCTestCase {
    private func tx(_ id: String, pending: Bool? = nil, reviewedAt: String? = nil,
                    ledgerId: String? = "personal") -> Tx {
        Tx(id: id, merchant: "m", amount: -10, account: "a", date: "2026-09-01",
           pending: pending, ledgerId: ledgerId, reviewedAt: reviewedAt)
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
        let ids = queue.filter { picked.contains($0.purchaseKey) }.map(\.id)
        let before = ReviewQueue.count(store.txns, ledgerId: ledger)

        XCTAssertEqual(store.markReviewed(ids), ids.count)

        let after = store.txns.filter { ids.contains($0.id) }
        XCTAssertTrue(after.allSatisfy { $0.reviewedAt != nil }, "every passed row is stamped")
        XCTAssertEqual(ReviewQueue.count(store.txns, ledgerId: ledger), before - ids.count,
                       "nothing outside the passed rows left the queue")
    }

    @MainActor
    func test_markReviewed_empty_is_a_noop() {
        XCTAssertEqual(FinchStore().markReviewed([]), 0)
    }
}
