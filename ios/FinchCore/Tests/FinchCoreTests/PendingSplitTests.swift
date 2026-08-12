import XCTest
@testable import FinchCore

/// `pendingSplit` decides what the "To confirm" queue is allowed to nag about.
final class PendingSplitTests: XCTestCase {
    private func tx(_ id: String, _ date: String, pending: Bool) -> Tx {
        Tx(id: id, merchant: "m", amount: -1, account: "a", date: date,
           pending: pending, ledgerId: "l")
    }

    func testConfirmedRowsAreInNeitherBucket() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-01", pending: false)], today: "2026-08-12")
        XCTAssertTrue(out.dueNow.isEmpty)
        XCTAssertTrue(out.upcoming.isEmpty)
    }

    func testPastAndTodayArePendingNow() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-01", pending: true),
                                          tx("b", "2026-08-12", pending: true)],
                                         today: "2026-08-12")
        XCTAssertEqual(out.dueNow.map(\.id), ["a", "b"])
        XCTAssertTrue(out.upcoming.isEmpty)
    }

    /// TODAY IS NOT UPCOMING. The boundary is `>`, not `>=` — a transaction entered
    /// today for later today must still be confirmable now, and that is the app's most
    /// common case, so the obvious slip would be the loudest one.
    func testTodayIsNotUpcoming() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-12", pending: true)], today: "2026-08-12")
        XCTAssertEqual(out.dueNow.map(\.id), ["a"])
        XCTAssertTrue(out.upcoming.isEmpty)
    }

    func testTomorrowOnwardsIsUpcoming() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-13", pending: true),
                                          tx("b", "2026-09-01", pending: true)],
                                         today: "2026-08-12")
        XCTAssertTrue(out.dueNow.isEmpty)
        XCTAssertEqual(out.upcoming.map(\.id), ["a", "b"])
    }

    /// The split is computed against `today`, so an upcoming row becomes due ON its date
    /// with nothing running — no migration, no background job, no state to get stuck.
    /// That property is the whole reason this is a selector and not a stored flag, so it
    /// is pinned here.
    func testARowMovesBucketWhenItsDateArrives() {
        let rent = [tx("rent", "2026-09-01", pending: true)]
        XCTAssertEqual(Selectors.pendingSplit(rent, today: "2026-08-31").upcoming.map(\.id), ["rent"])
        XCTAssertEqual(Selectors.pendingSplit(rent, today: "2026-09-01").dueNow.map(\.id), ["rent"])
    }

    /// Input order is preserved within each bucket — callers sort afterwards, and a
    /// selector that quietly reordered would make their sort look broken.
    func testOrderIsPreservedWithinEachBucket() {
        let out = Selectors.pendingSplit([tx("c", "2026-08-03", pending: true),
                                          tx("a", "2026-08-01", pending: true)],
                                         today: "2026-08-12")
        XCTAssertEqual(out.dueNow.map(\.id), ["c", "a"])
    }
}
