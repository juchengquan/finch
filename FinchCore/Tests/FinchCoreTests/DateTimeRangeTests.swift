import XCTest
import GRDB
@testable import FinchCore

/// Phase 4 of "date **and** time on every editable date": the two remaining
/// read-side date inputs — the transaction feed's from/to range, and reconcile's
/// statement date — carry a time of day.
///
/// The rule is the one phase 3 established and this suite re-asserts at both ends:
/// **a bare date behaves exactly as it always has, and "00:00" IS a bare date.**
/// Everything else here is the difference a real time makes.
final class DateTimeRangeTests: XCTestCase {

    // MARK: the feed's range

    private func tx(_ id: String, _ date: String, _ time: String?) -> Tx {
        Tx(id: id, merchant: "M", category: nil, amount: -10, account: "a1",
           date: date, pending: false, ledgerId: "l1", time: time)
    }

    private var feed: [Tx] {
        [tx("t1", "2026-05-01", "08:00"),
         tx("t2", "2026-05-01", "18:00"),
         tx("t3", "2026-05-02", "08:00"),
         tx("t4", "2026-05-02", nil)]      // no time of its own → midnight
    }

    private func ids(from: String? = nil, to: String? = nil) -> [String] {
        Selectors.selectTransactions(feed, ListOptions(ledgerId: "l1", from: from, to: to))
            .map(\.id).sorted()
    }

    /// A date-only range is a whole-day range, inclusive at both ends — unchanged.
    func test_dateOnlyRange_isUnchanged() {
        XCTAssertEqual(ids(from: "2026-05-01", to: "2026-05-01"), ["t1", "t2"])
        XCTAssertEqual(ids(from: "2026-05-02"), ["t3", "t4"])
        XCTAssertEqual(ids(to: "2026-05-02"), ["t1", "t2", "t3", "t4"])
    }

    /// With a time, the bound is a MOMENT: "from 12:00 on the 1st" drops the 08:00
    /// and keeps the 18:00, which a whole-day range cannot express.
    func test_aTimedLowerBoundCutsWithinTheDay() {
        XCTAssertEqual(ids(from: "2026-05-01 12:00"), ["t2", "t3", "t4"])
    }

    /// And the upper bound is INCLUSIVE — "to 08:00" keeps an 08:00 transaction.
    /// A filter range is what the user typed, unlike a budget cycle whose top
    /// boundary belongs to the next window.
    func test_aTimedUpperBoundIsInclusive() {
        XCTAssertEqual(ids(to: "2026-05-02 08:00"), ["t1", "t2", "t3", "t4"])
        XCTAssertEqual(ids(to: "2026-05-02 07:59"), ["t1", "t2", "t4"])
    }

    /// A transaction with no time reads as midnight — so a lower bound anywhere
    /// inside its day excludes it. Same assumption every date-only comparison in
    /// the engine already makes.
    func test_aTransactionWithoutATimeReadsAsMidnight() {
        XCTAssertEqual(ids(from: "2026-05-02 00:01"), ["t3"])
    }

    // MARK: reconcile's statement moment

    func test_reconcile_withoutATime_storesThePlainDate() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(1200),
            "statementDate": .string("2026-05-01")]))
        let a = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a1" })
        XCTAssertEqual(a.lastReconciledAt, "2026-05-01")
    }

    /// "00:00" is midnight, which is what a date-only checkpoint already means — so
    /// it must not change what gets stored. Without this every reconcile from the
    /// sheet would write a different string than before, because the picker always
    /// produces a time.
    func test_reconcile_atMidnight_storesThePlainDate() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(1200),
            "statementDate": .string("2026-05-01"), "statementTime": .string("00:00")]))
        let a = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a1" })
        XCTAssertEqual(a.lastReconciledAt, "2026-05-01")
    }

    func test_reconcile_withATime_storesTheMoment() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(1200),
            "statementDate": .string("2026-05-01"), "statementTime": .string("09:15")]))
        let a = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a1" })
        XCTAssertEqual(a.lastReconciledAt, "2026-05-01 09:15")
        // Every reader of the checkpoint slices to 10 chars, so the freshness
        // selector must be unmoved by the suffix.
        XCTAssertEqual(Selectors.reconcileStatus(a.lastReconciledAt, "2026-05-02"), .fresh(days: 1))
    }

    /// The adjustment reconcile posts is dated to the statement; it is now timed to
    /// it too, so it does not sink below the transactions it accounts for.
    func test_reconcile_adjustmentCarriesTheStatementTime() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(1200),
            "statementDate": .string("2026-05-01"), "statementTime": .string("09:15"),
            "postAdjustment": .bool(true)]))
        try q.read { db in
            let row = try XCTUnwrap(try Row.fetchOne(db, sql:
                "SELECT date, time FROM entries WHERE kind = 'adjustment'"))
            XCTAssertEqual(row["date"] as String?, "2026-05-01")
            XCTAssertEqual(row["time"] as String?, "09:15")
        }
    }

    func test_reconcile_rejectsAMalformedTime() throws {
        let q = try TestSeed.base()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(1200),
            "statementDate": .string("2026-05-01"), "statementTime": .string("9:15")])))
    }
}
