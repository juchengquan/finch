import XCTest
@testable import FinchApp
import FinchCore

/// A transfer between your own accounts, as the feed shows it: two rows, one per
/// account leg. Both rows used to read just "Transfer", and the month header summed
/// them by sign — so a $250 transfer added $250 to the ledger's in AND its out.
///
/// Run against a transfer really posted to the sample pack rather than hand-built rows,
/// because what matters is that the legs the PROJECTION emits pair up: the pure rule is
/// covered in `MonthGroupingTests`.
@MainActor
final class TransferRowTitleTests: XCTestCase {

    private func loadedStore() async throws -> FinchStore {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: url))
        return store
    }

    /// Post a $250 transfer between two same-currency accounts of the pack, and return
    /// its legs as the projection emits them: (the leg that left, the leg that arrived).
    /// The pack has no transfer of its own.
    private func transferLegs(_ store: FinchStore) throws -> (out: Tx, in: Tx) {
        let accts = store.accounts.filter { $0.isActive != false }
        guard let from = accts.first,
              let to = accts.dropFirst().first(where: { $0.currency == from.currency })
        else { throw XCTSkip("the pack has no two same-currency accounts") }
        let date = try XCTUnwrap(store.txns.map(\.date).max())
        try store.apply(.createTransfer, Args([
            "fromAccountId": .string(from.id), "toAccountId": .string(to.id),
            "fromAmount": .double(250), "date": .string(date)]))
        let legs = store.txns.filter { $0.kind == "transfer" && $0.date == date && abs($0.amount) == 250 }
        let out = try XCTUnwrap(legs.first { $0.amount < 0 }, "no outgoing leg projected")
        let arrived = try XCTUnwrap(legs.first { $0.amount > 0 }, "no arriving leg projected")
        XCTAssertNotNil(out.transferGroupId)
        XCTAssertEqual(out.transferGroupId, arrived.transferGroupId)
        return (out, arrived)
    }

    private func name(_ store: FinchStore, _ accountId: String) throws -> String {
        try XCTUnwrap(store.accounts.first { $0.id == accountId }?.name)
    }

    func test_eachLegSaysWhereTheMoneyWentOrCameFrom() async throws {
        let store = try await loadedStore()
        let (out, arrived) = try transferLegs(store)
        XCTAssertEqual(store.transferTitle(for: out), "To \(try name(store, arrived.account))")
        XCTAssertEqual(store.transferTitle(for: arrived), "From \(try name(store, out.account))")
    }

    func test_nonTransferRowsHaveNoTransferTitle() async throws {
        let store = try await loadedStore()
        let other = try XCTUnwrap(store.txns.first { $0.kind != "transfer" })
        XCTAssertNil(store.transferTitle(for: other))
    }

    /// The month header over the ledger-wide rows: the transfer counts in neither in nor
    /// out. Over one account's rows it counts, on the side it moved.
    func test_monthFigures_ledgerWideDropTheTransfer_oneAccountKeepsIt() async throws {
        let store = try await loadedStore()
        let (out, arrived) = try transferLegs(store)
        let month = String(out.date.prefix(7))
        let monthTx = store.txns.filter { $0.date.hasPrefix(month) }
        let others = monthTx.filter { $0.transferGroupId != out.transferGroupId }

        XCTAssertEqual(MonthGrouping.income(monthTx), MonthGrouping.income(others), accuracy: 0.005)
        XCTAssertEqual(MonthGrouping.expense(monthTx), MonthGrouping.expense(others), accuracy: 0.005)

        let fromAccount = monthTx.filter { $0.account == out.account }
        XCTAssertEqual(MonthGrouping.expense(fromAccount),
                       MonthGrouping.expense(fromAccount.filter { $0.id != out.id }) - out.amount,
                       accuracy: 0.005)
        let toAccount = monthTx.filter { $0.account == arrived.account }
        XCTAssertEqual(MonthGrouping.income(toAccount),
                       MonthGrouping.income(toAccount.filter { $0.id != arrived.id }) + arrived.amount,
                       accuracy: 0.005)
    }
}
