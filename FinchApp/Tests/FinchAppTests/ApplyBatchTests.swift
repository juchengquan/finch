import XCTest
@testable import FinchApp
import FinchCore

/// `FinchStore.applyBatch` — the daily FX refresh's batched write path. All
/// ops land through the chokepoint, a bad row is skipped without sinking the
/// rest, and the projected state reflects the batch (side effects fire once,
/// which is the point — audit 2026-07-22, the foreground jam).
final class ApplyBatchTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: name, withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
    }

    private func rateOp(_ currency: String, _ rate: Double) -> (action: ActionName, args: Args) {
        (.setExchangeRate, Args([
            "date": .string("2026-07-22"), "currency": .string(currency),
            "rate": .double(rate), "source": .string("test")]))
    }

    @MainActor
    func test_applyBatch_applies_all_and_reprojects_once_at_end() async throws {
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: fixture("sample")))

        let applied = store.applyBatch([rateOp("EUR", 1.08), rateOp("GBP", 1.27), rateOp("JPY", 0.0067)])
        XCTAssertEqual(applied, 3)

        // The batch is visible in the projected state.
        let got = store.exchangeRates.filter { $0.date == "2026-07-22" && $0.source == "test" }
        XCTAssertEqual(Set(got.map(\.currency)), ["EUR", "GBP", "JPY"])
    }

    @MainActor
    func test_applyBatch_skips_bad_rows_and_keeps_the_rest() async throws {
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: fixture("sample")))

        // Middle op is invalid (missing required args) — engine rejects it.
        let bad: (action: ActionName, args: Args) = (.setExchangeRate, Args([:]))
        let applied = store.applyBatch([rateOp("EUR", 1.08), bad, rateOp("GBP", 1.27)])
        XCTAssertEqual(applied, 2)
        let got = store.exchangeRates.filter { $0.date == "2026-07-22" && $0.source == "test" }
        XCTAssertEqual(Set(got.map(\.currency)), ["EUR", "GBP"])
    }

    @MainActor
    func test_applyBatch_empty_is_a_noop() {
        let store = FinchStore()
        XCTAssertEqual(store.applyBatch([]), 0)
    }
}
