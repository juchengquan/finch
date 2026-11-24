import XCTest
import FinchCore
@testable import FinchApp

/// Changing a card's type keeps its card fields, so a mistaken switch loses
/// nothing. The statement and due days survived it; the credit limit was wiped.
@MainActor
final class AccountTypeChangeTests: XCTestCase {

    func test_changingACardsTypeKeepsItsLimit() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let id = "card-\(UUID().uuidString.prefix(6))"
        try store.apply(.createAccount, Args([
            "id": .string(id), "ledgerId": .string(store.activeLedgerId), "name": .string("Visa"),
            "type": .string("credit_card"), "currency": .string(store.baseCurrency),
            "creditLimit": .double(5000), "statementDay": .int(12), "dueDay": .int(5)]))

        XCTAssertEqual(AccountSheet.cardPatch(isCard: false, creditLimit: "5000", statementDay: 12, dueDay: 5), [:])
        var patch: [String: JSONValue] = ["name": .string("Visa"), "type": .string("savings")]
        patch.merge(AccountSheet.cardPatch(isCard: false, creditLimit: "5000", statementDay: 12, dueDay: 5)) { $1 }
        try store.apply(.updateAccount, Args(["id": .string(id), "patch": .object(patch)]))

        let account = try XCTUnwrap(store.accounts.first { $0.id == id })
        XCTAssertEqual(account.type, "savings")
        XCTAssertEqual(account.creditLimit, 5000)
        XCTAssertEqual(account.statementDay, 12)

        // On a card, an emptied limit field still clears it.
        XCTAssertEqual(AccountSheet.cardPatch(isCard: true, creditLimit: "", statementDay: 0, dueDay: 0)["creditLimit"], .null)
    }
}
