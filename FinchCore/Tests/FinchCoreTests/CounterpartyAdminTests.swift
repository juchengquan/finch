import XCTest
import GRDB
@testable import FinchCore

/// Counterparty CRUD + verify, and the isVerified flag now exposed on the
/// Counterparty projection (backing the merchants admin screen).
final class CounterpartyAdminTests: XCTestCase {
    func test_crud_verify_and_projection() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createCounterparty", args: Args(["id": .string("cp1"), "ledgerId": .string("l1"), "name": .string("Acme")]))
        var cp = try Projection.counterparties(dbQueue: q, ledgerId: "l1").first { $0.id == "cp1" }
        XCTAssertEqual(cp?.name, "Acme")
        XCTAssertEqual(cp?.isVerified, false)

        try Apply.apply(dbQueue: q, action: "verifyCounterparty", args: Args(["id": .string("cp1")]))
        cp = try Projection.counterparties(dbQueue: q, ledgerId: "l1").first { $0.id == "cp1" }
        XCTAssertEqual(cp?.isVerified, true)

        try Apply.apply(dbQueue: q, action: "updateCounterparty", args: Args(["id": .string("cp1"), "patch": .object(["name": .string("Acme Corp")])]))
        try Apply.apply(dbQueue: q, action: "unverifyCounterparty", args: Args(["id": .string("cp1")]))
        cp = try Projection.counterparties(dbQueue: q, ledgerId: "l1").first { $0.id == "cp1" }
        XCTAssertEqual(cp?.name, "Acme Corp")
        XCTAssertEqual(cp?.isVerified, false)

        try Apply.apply(dbQueue: q, action: "deleteCounterparty", args: Args(["id": .string("cp1")]))
        XCTAssertTrue(try Projection.counterparties(dbQueue: q, ledgerId: "l1").isEmpty)
    }
}
