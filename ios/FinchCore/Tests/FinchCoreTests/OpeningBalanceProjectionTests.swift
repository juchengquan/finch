import XCTest
import GRDB
@testable import FinchCore

final class OpeningBalanceProjectionTests: XCTestCase {
    func test_projection_carries_opening_balance() throws {
        let q = try TestSeed.base()   // l1 (USD base)
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Checking"),
            "type": .string("cash"), "currency": .string("USD"), "openingBalance": .double(500)]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a3"), "ledgerId": .string("l1"), "name": .string("Empty"),
            "type": .string("cash"), "currency": .string("USD")]))   // no opening

        let accts = try Projection.accounts(dbQueue: q, ledgerId: "l1")
        let a2 = try XCTUnwrap(accts.first { $0.id == "a2" })
        let a3 = try XCTUnwrap(accts.first { $0.id == "a3" })
        XCTAssertEqual(a2.openingBalanceBase ?? -1, 500, accuracy: 0.001)
        XCTAssertNil(a3.openingBalanceBase)
    }
}
