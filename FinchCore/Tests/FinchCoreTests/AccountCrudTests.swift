import XCTest
import GRDB
@testable import FinchCore

/// Coverage for the account CRUD + account-group actions the iOS UI now exposes,
/// and the archived-accounts projection that backs the unarchive view.
final class AccountCrudTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue { try TestSeed.base() }   // l1 / a1 / c1

    func test_createAccount_basic() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Visa"),
            "type": .string("credit_card"), "currency": .string("USD"),
        ]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM accounts WHERE id='a2'"), "Visa")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT type FROM accounts WHERE id='a2'"), "credit_card")
            // credit_card is included in net worth by default (counts as a liability).
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT include_in_net_worth FROM accounts WHERE id='a2'"), 1)
        }
    }

    func test_createAccount_openingBalancePostsEntry() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("savings"), "currency": .string("USD"), "openingBalance": .double(1000),
        ]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? 0, 1000, accuracy: 0.001)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind='opening' AND id='open-a2'"), 1)
        }
    }

    func test_setOpeningBalance_addChangeRemove() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("savings"), "currency": .string("USD"), "openingBalance": .double(1000),
        ]))
        // Post a real transaction on top so recompute has more than the opening.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a2"), "amount": .double(-100),
            "merchant": .string("x"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        let originalDate = try q.read { db in try String.fetchOne(db, sql: "SELECT date FROM entries WHERE id='open-a2'") }

        // Change: balance follows (1000-100 → 250-100), entry keeps its date and
        // stays the pre-cleared reconcile anchor; double-entry stays balanced.
        try Apply.apply(dbQueue: q, action: "setOpeningBalance", args: Args(["id": .string("a2"), "amount": .double(250)]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? 0, 150, accuracy: 0.001)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT date FROM entries WHERE id='open-a2'"), originalDate)
            XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT cleared_at FROM postings WHERE entry_id='open-a2' AND account_id='a2'"))
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT SUM(amount_base) FROM postings WHERE entry_id='open-a2'") ?? -1, 0, accuracy: 0.001)
        }
        XCTAssertEqual(try Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a2" }?.openingBalance ?? 0, 250, accuracy: 0.001)

        // Remove (0): entry gone, balance is transactions only.
        try Apply.apply(dbQueue: q, action: "setOpeningBalance", args: Args(["id": .string("a2"), "amount": .double(0)]))
        try q.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM entries WHERE id='open-a2'"))
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? 0, -100, accuracy: 0.001)
        }

        // Add to an account that never had one (a1) — entry appears, balance seeds.
        try Apply.apply(dbQueue: q, action: "setOpeningBalance", args: Args(["id": .string("a1"), "amount": .double(75)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE id='open-a1' AND kind='opening'"), 1)
        }

        // Unknown account rejects.
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "setOpeningBalance", args: Args(["id": .string("nope"), "amount": .double(1)]))) { err in
            XCTAssertEqual((err as? I18nError)?.code, "error.notFound.account")
        }
    }

    func test_updateAccount_patches() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "updateAccount", args: Args([
            "id": .string("a1"), "patch": .object([
                "name": .string("Renamed"), "type": .string("savings"), "includeInNetWorth": .int(0),
            ]),
        ]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM accounts WHERE id='a1'"), "Renamed")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT include_in_net_worth FROM accounts WHERE id='a1'"), 0)
        }
    }

    func test_deleteAccount_emptyOk_butRejectsWithTransactions() throws {
        let q = try seeded()
        // Empty extra account deletes cleanly.
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args(["id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Temp"), "type": .string("cash"), "currency": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "deleteAccount", args: Args(["id": .string("a2")]))
        try q.read { db in XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM accounts WHERE id='a2'")) }

        // a1 with a transaction is protected.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string("x"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "deleteAccount", args: Args(["id": .string("a1")]))) { err in
            XCTAssertEqual((err as? I18nError)?.code, "error.account.hasTransactions")
        }
    }

    func test_archive_movesAccountBetweenProjections() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "archiveAccount", args: Args(["id": .string("a1")]))
        XCTAssertTrue(try Projection.accounts(dbQueue: q, ledgerId: "l1").isEmpty)
        XCTAssertEqual(try Projection.archivedAccounts(dbQueue: q, ledgerId: "l1").map(\.id), ["a1"])
        try Apply.apply(dbQueue: q, action: "unarchiveAccount", args: Args(["id": .string("a1")]))
        XCTAssertEqual(try Projection.accounts(dbQueue: q, ledgerId: "l1").map(\.id), ["a1"])
        XCTAssertTrue(try Projection.archivedAccounts(dbQueue: q, ledgerId: "l1").isEmpty)
    }

    func test_accountGroup_crud_and_projection() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createAccountGroup", args: Args(["id": .string("g1"), "ledgerId": .string("l1"), "name": .string("Cash")]))
        XCTAssertEqual(try Projection.accountGroups(dbQueue: q, ledgerId: "l1").map(\.name), ["Cash"])
        try Apply.apply(dbQueue: q, action: "updateAccountGroup", args: Args(["id": .string("g1"), "patch": .object(["name": .string("Liquid")])]))
        XCTAssertEqual(try Projection.accountGroups(dbQueue: q, ledgerId: "l1").first?.name, "Liquid")
        try Apply.apply(dbQueue: q, action: "deleteAccountGroup", args: Args(["id": .string("g1")]))
        XCTAssertTrue(try Projection.accountGroups(dbQueue: q, ledgerId: "l1").isEmpty)
    }
}
