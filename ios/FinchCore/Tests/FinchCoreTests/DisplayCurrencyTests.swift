import XCTest
import GRDB
@testable import FinchCore

/// setDisplayCurrency persists a per-ledger choice into
/// app_state.displayCurrencyByLedger; the projection reads it back.
final class DisplayCurrencyTests: XCTestCase {
    func test_setDisplayCurrency_roundTripsPerLedger() throws {
        let q = try TestSeed.base()   // ledger l1
        XCTAssertTrue(try Projection.displayCurrencyByLedger(dbQueue: q).isEmpty)

        try Apply.apply(dbQueue: q, action: "setDisplayCurrency", args: Args(["ledgerId": .string("l1"), "currency": .string("EUR")]))
        XCTAssertEqual(try Projection.displayCurrencyByLedger(dbQueue: q)["l1"], "EUR")

        // A second ledger's choice is independent; re-setting l1 overwrites.
        try Apply.apply(dbQueue: q, action: "setDisplayCurrency", args: Args(["ledgerId": .string("l2"), "currency": .string("JPY")]))
        try Apply.apply(dbQueue: q, action: "setDisplayCurrency", args: Args(["ledgerId": .string("l1"), "currency": .string("GBP")]))
        let map = try Projection.displayCurrencyByLedger(dbQueue: q)
        XCTAssertEqual(map["l1"], "GBP")
        XCTAssertEqual(map["l2"], "JPY")
    }
}
