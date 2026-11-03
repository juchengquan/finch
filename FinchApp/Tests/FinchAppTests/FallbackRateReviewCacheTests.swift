import XCTest
@testable import FinchApp
import FinchCore

/// `FinchStore.fallbackRateReview` — the 1:1-rate review Currencies re-reads after
/// every write. It used to scan the postings on the main thread each time, once
/// per suspect rate; now it is computed again only when something it reads from
/// changed: a rate, a ledger's base, or a transaction in another currency.
///
/// `fallbackReviewRunCount` is the seam: each claim below is about when it moves.
@MainActor
final class FallbackRateReviewCacheTests: XCTestCase {

    private func loadedStore() async throws -> FinchStore {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: url))
        await store.awaitTxnsReady()
        return store
    }

    private func base(_ store: FinchStore) throws -> String {
        try XCTUnwrap(store.ledgers.first { $0.id == store.activeLedgerId }?.base)
    }

    private func spend(_ store: FinchStore, account: String, _ amount: Double) throws {
        try store.apply(.addTransaction, Args([
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(account),
            "amount": .double(amount), "merchant": .string("Cache test"),
            "date": .string(store.wallToday), "skipRules": .bool(true)]))
    }

    /// Reading it twice, or after a write in the ledger's own currency, reuses it.
    func test_aWriteInTheBaseCurrencyDoesNotRescan() async throws {
        let store = try await loadedStore()
        let base = try base(store)
        let account = try XCTUnwrap(store.accounts.first { $0.currency == base }).id

        let first = store.fallbackRateReview()
        let runs = store.fallbackReviewRunCount
        XCTAssertEqual(store.fallbackRateReview(), first)
        try spend(store, account: account, -12)
        try spend(store, account: account, -7.5)
        XCTAssertEqual(store.fallbackRateReview(), first)
        XCTAssertEqual(store.fallbackReviewRunCount, runs, "a write in the base currency rescanned")
    }

    /// A rate, or an entry in another currency, can change what it finds.
    func test_aRateOrAForeignEntryRescans() async throws {
        let store = try await loadedStore()
        _ = store.fallbackRateReview()
        var runs = store.fallbackReviewRunCount

        try store.apply(.setExchangeRate, Args([
            "date": .string(store.wallToday), "currency": .string("KRW"),
            "rate": .double(0.00072), "source": .string("manual")]))
        _ = store.fallbackRateReview()
        XCTAssertEqual(store.fallbackReviewRunCount, runs + 1, "a new rate did not rescan")
        runs = store.fallbackReviewRunCount

        try store.apply(.createAccount, Args([
            "id": .string("cache-won"), "ledgerId": .string(store.activeLedgerId),
            "name": .string("Won"), "type": .string("cash"), "currency": .string("KRW")]))
        _ = store.fallbackRateReview()
        XCTAssertEqual(store.fallbackReviewRunCount, runs, "an account with nothing in it rescanned")

        try spend(store, account: "cache-won", -50000)
        _ = store.fallbackRateReview()
        XCTAssertEqual(store.fallbackReviewRunCount, runs + 1, "an entry in another currency did not rescan")
    }
}
