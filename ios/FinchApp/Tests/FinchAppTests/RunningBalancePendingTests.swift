import XCTest
@testable import FinchApp
import FinchCore

/// The running-balance column and the account balance must agree.
///
/// They did not. `runningBalanceBase` walked every transaction and never looked at
/// `pending`, while an account's stored balance counts only confirmed ones — two
/// rules for the same quantity. Observed on a device and reproduced on the seeded
/// simulator: setting a $4,200 salary to pending dropped the account title from
/// $11,453.50 to $7,253.50 and left every row's running balance untouched, so the
/// newest row claimed a balance $4,200 above the one printed directly over it.
///
/// It read as "the number doesn't change", which sounds like a refresh bug and is
/// not one: the cache rebuilt correctly and produced the same figures, because by
/// the walk's own rule nothing had changed — same row, same amount, only its status.
@MainActor
final class RunningBalancePendingTests: XCTestCase {

    private func loadedStore() async throws -> FinchStore {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: url))
        return store
    }

    /// The newest confirmed transaction on an account, and that account.
    private func newestConfirmed(_ store: FinchStore) throws -> (tx: Tx, account: AccountRow) {
        for t in store.txns where t.pending != true {
            if let a = store.accounts.first(where: { $0.id == t.account }) { return (t, a) }
        }
        throw XCTSkip("the pack has no confirmed transaction on a known account")
    }

    /// The invariant, stated once: the newest confirmed row's running balance IS the
    /// account's balance. Everything below follows from breaking it.
    func test_newestConfirmedRowMatchesTheAccountBalance() async throws {
        let store = try await loadedStore()
        let (tx, account) = try newestConfirmed(store)

        let running = try XCTUnwrap(store.runningBalanceBase(for: tx),
                                    "a confirmed row must have a running balance")
        XCTAssertEqual(running, account.balance, accuracy: 0.005,
                       "the newest confirmed row on \(account.name ?? account.id) says \(running) " +
                       "while the account says \(account.balance)")
    }

    /// The reported bug, as a sequence: confirm → set pending → the column must move
    /// with the balance, not sit still.
    func test_settingPending_movesTheRunningBalanceWithTheAccountBalance() async throws {
        let store = try await loadedStore()
        let (tx, account) = try newestConfirmed(store)
        let amount = tx.amount

        let balanceBefore = account.balance
        let runningBefore = try XCTUnwrap(store.runningBalanceBase(for: tx))
        XCTAssertEqual(runningBefore, balanceBefore, accuracy: 0.005)

        try store.apply(.updateTransaction, Args([
            "id": .string(tx.id), "patch": .object(["status": .string("pending")])]))

        let after = try XCTUnwrap(store.accounts.first { $0.id == account.id })
        XCTAssertEqual(after.balance, balanceBefore - amount, accuracy: 0.005,
                       "the account balance did not drop the pending amount — premise broken")

        // The row that is now pending has no "balance after", because it has not
        // cleared. Printing the preceding confirmed figure would be a number that is
        // not true of this row.
        XCTAssertNil(store.runningBalanceBase(for: tx),
                     "a pending row still reports a running balance")

        // And the row below it now ends the series, at the account's new balance.
        let nextConfirmed = store.txns.first { $0.pending != true && $0.account == account.id }
        if let next = nextConfirmed {
            let running = try XCTUnwrap(store.runningBalanceBase(for: next))
            XCTAssertEqual(running, after.balance, accuracy: 0.005,
                           "the newest confirmed row says \(running), the account says \(after.balance) " +
                           "— the column is computing over a different set than the balance")
        }
    }

    /// And back again, so the fix is not one-directional.
    func test_confirmingAgain_restoresTheColumn() async throws {
        let store = try await loadedStore()
        let (tx, account) = try newestConfirmed(store)
        let before = try XCTUnwrap(store.runningBalanceBase(for: tx))

        try store.apply(.updateTransaction, Args([
            "id": .string(tx.id), "patch": .object(["status": .string("pending")])]))
        XCTAssertNil(store.runningBalanceBase(for: tx))

        try store.apply(.confirmTransaction, Args(["id": .string(tx.id)]))

        let restored = try XCTUnwrap(store.runningBalanceBase(for: tx))
        XCTAssertEqual(restored, before, accuracy: 0.005, "confirming did not restore the figure")
        let acct = try XCTUnwrap(store.accounts.first { $0.id == account.id })
        XCTAssertEqual(restored, acct.balance, accuracy: 0.005)
    }
}
