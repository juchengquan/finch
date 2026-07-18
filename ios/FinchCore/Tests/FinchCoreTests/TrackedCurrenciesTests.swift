import XCTest
import GRDB
@testable import FinchCore

/// setTrackedCurrencies persists the global FX auto-update fetch list into
/// app_state.fxTrackedCurrencies; the projection reads it back (nil when the
/// key was never written — seeded-default mode).
final class TrackedCurrenciesTests: XCTestCase {
    func test_setTrackedCurrencies_roundTrips_normalizes_andDistinguishesAbsentFromEmpty() throws {
        let q = try TestSeed.base()
        XCTAssertNil(try Projection.trackedCurrencies(dbQueue: q))   // absent ≠ []

        // normalizes: trims, uppercases, drops USD + empties, de-dups, sorts
        try Apply.apply(dbQueue: q, action: "setTrackedCurrencies",
                        args: Args(["codes": .array([.string(" eur "), .string("JPY"), .string("eur"), .string("USD"), .string("")])]))
        XCTAssertEqual(try Projection.trackedCurrencies(dbQueue: q), ["EUR", "JPY"])

        // empty list is stored and read back as [], not nil
        try Apply.apply(dbQueue: q, action: "setTrackedCurrencies", args: Args(["codes": .array([])]))
        XCTAssertEqual(try Projection.trackedCurrencies(dbQueue: q), [])
    }
}
