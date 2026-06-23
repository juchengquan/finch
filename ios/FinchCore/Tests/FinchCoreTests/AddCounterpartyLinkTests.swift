import XCTest
import GRDB
@testable import FinchCore

final class AddCounterpartyLinkTests: XCTestCase {
    private func addArgs(_ merchant: String) -> Args {
        Args(["ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
              "merchant": .string(merchant), "categoryId": .string("c1"), "date": .string("2026-06-01")])
    }
    private func counterpartyId(_ q: DatabaseQueue, _ eid: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT counterparty_id FROM entries WHERE id = ?", arguments: [eid]) }
    }

    func test_addTransaction_linksExistingCounterpartyByName_caseInsensitive() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createCounterparty",
                        args: Args(["id": .string("cp1"), "ledgerId": .string("l1"), "name": .string("Starbucks")]))
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: addArgs("starbucks"))
        XCTAssertEqual(try counterpartyId(q, eid!), "cp1")
    }

    func test_addTransaction_unknownMerchant_leavesCounterpartyNull_noAutoCreate() throws {
        let q = try TestSeed.base()
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: addArgs("Nowhere"))
        XCTAssertNil(try counterpartyId(q, eid!))
        let cpCount = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE ledger_id = 'l1'") }
        XCTAssertEqual(cpCount, 0)   // never auto-creates
    }
}
