import XCTest
import GRDB
@testable import FinchCore

/// setBudgetOrder persists a per-ledger manual budget order into
/// app_state.budgetOrderByLedger; the projection reads it back.
final class BudgetOrderTests: XCTestCase {
    func test_setBudgetOrder_roundTrips_andMergesPerLedger() throws {
        let q = try TestSeed.base()   // ledger l1
        XCTAssertTrue(try Projection.budgetOrderByLedger(dbQueue: q).isEmpty)

        try Apply.apply(dbQueue: q, action: "setBudgetOrder",
                        args: Args(["ledgerId": .string("l1"), "budgetIds": .array([.string("b2"), .string("b1")])]))
        XCTAssertEqual(try Projection.budgetOrderByLedger(dbQueue: q)["l1"], ["b2", "b1"])

        // A second ledger's order merges (doesn't clobber); re-setting l1 overwrites.
        try Apply.apply(dbQueue: q, action: "setBudgetOrder",
                        args: Args(["ledgerId": .string("l2"), "budgetIds": .array([.string("t1")])]))
        let map = try Projection.budgetOrderByLedger(dbQueue: q)
        XCTAssertEqual(map["l1"], ["b2", "b1"])
        XCTAssertEqual(map["l2"], ["t1"])
    }
}
