import XCTest
@testable import FinchApp
import FinchCore

/// Pure grouping/derivation helpers behind the Exchange rates pages.
final class FxDeriveTests: XCTestCase {
    private let rates = [
        ExchangeRate(date: "2026-07-16", currency: "EUR", rate: 1.14, source: "ECB"),
        ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 1.15, source: "ECB"),
        ExchangeRate(date: "2026-07-17", currency: "CAD", rate: 0.71, source: nil),
        ExchangeRate(date: "2026-07-15", currency: "EUR", rate: 1.13, source: "manual"),
    ]

    func test_currencies_sortedDeduped() {
        XCTAssertEqual(fxCurrencies(rates), ["CAD", "EUR"])
        XCTAssertEqual(fxCurrencies([]), [])
    }

    func test_latest_picksMaxDate_nilWhenAbsent() {
        XCTAssertEqual(fxLatest(rates, "EUR")?.rate, 1.15)
        XCTAssertEqual(fxLatest(rates, "CAD")?.rate, 0.71)
        XCTAssertNil(fxLatest(rates, "JPY"))
    }

    func test_latest_equalDates_laterRowInListOrderWins() {
        let dup = rates + [ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 9.99, source: "manual")]
        XCTAssertEqual(fxLatest(dup, "EUR")?.rate, 9.99)
    }

    func test_series_dateAscending() {
        XCTAssertEqual(fxSeries(rates, "EUR"), [1.13, 1.14, 1.15])
        XCTAssertEqual(fxSeries(rates, "JPY"), [])
    }

    // MARK: 'derived' copies

    /// What older versions saved under each conversion's date: a copy of the rate
    /// the conversion used. KRW's newest row copies a mistyped rate the user has
    /// since corrected by hand; the engine's lookup skips it, so the pages must too.
    private let krw = [
        ExchangeRate(date: "2026-05-01", currency: "KRW", rate: 0.00072, source: "ECB"),
        ExchangeRate(date: "2026-05-10", currency: "KRW", rate: 0.00073, source: "manual"),
        ExchangeRate(date: "2026-05-20", currency: "KRW", rate: 0.0073, source: "derived"),
    ]

    func test_latest_skipsDerivedCopies() {
        XCTAssertEqual(fxLatest(krw, "KRW")?.rate, 0.00073)
    }

    func test_series_andHistory_skipDerivedCopies() {
        XCTAssertEqual(fxSeries(krw, "KRW"), [0.00072, 0.00073])
        XCTAssertEqual(fxHistory(krw, "KRW").map(\.date), ["2026-05-10", "2026-05-01"])   // newest first
    }

    /// A currency whose only rows are copies has no rate, as for the engine.
    func test_onlyDerivedRows_readAsNoRate() {
        let thb = [ExchangeRate(date: "2026-05-14", currency: "THB", rate: 1, source: "derived")]
        XCTAssertNil(fxLatest(thb, "THB"))
        XCTAssertEqual(fxSeries(thb, "THB"), [])
        XCTAssertEqual(fxHistory(thb, "THB"), [])
    }

    func test_displayDay_formats_andFallsBack() {
        // en_US-style abbreviated month-day; assert on components to stay locale-tolerant.
        let s = fxDisplayDay("2026-07-17")
        XCTAssertTrue(s.contains("17"))
        XCTAssertFalse(s.contains("2026"))
        XCTAssertTrue(fxDisplayDay("2026-07-17", withYear: true).contains("2026"))
        XCTAssertEqual(fxDisplayDay("garbage"), "garbage")
    }

    func test_effectiveTracked_absentFallsBack_emptyIsRespected() {
        XCTAssertEqual(fxEffectiveTracked(stored: nil, fallback: ["CAD", "EUR"]), ["CAD", "EUR"])
        XCTAssertEqual(fxEffectiveTracked(stored: [], fallback: ["CAD", "EUR"]), [])   // user untracked everything
        XCTAssertEqual(fxEffectiveTracked(stored: ["JPY"], fallback: ["CAD", "EUR"]), ["JPY"])
    }
}

/// Currencies-page row models: ordering (hub → tracked A–Z → rest A–Z) + search.
@MainActor
final class FxCurrencyRowsTests: XCTestCase {
    private let rates = [
        ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 1.15, source: "ECB"),
    ]

    func test_rows_hubFirst_thenTrackedAZ_thenRestAZ_withRates() {
        let rows = fxCurrencyRows(all: ["JPY", "EUR", "USD", "CAD", "AED"], rates: rates,
                                  tracked: ["JPY", "EUR"], grouping: ["JPY", "EUR"])
        XCTAssertEqual(rows.map(\.code), ["USD", "EUR", "JPY", "AED", "CAD"])
        XCTAssertTrue(rows[0].isHub)
        XCTAssertEqual(rows[0].rate, 1.0)
        XCTAssertFalse(rows[0].tracked)
        XCTAssertEqual(rows[1].rate, 1.15)          // EUR has a stored rate
        XCTAssertTrue(rows[1].tracked)
        XCTAssertNil(rows[2].rate)                  // JPY tracked but no rate yet
        XCTAssertFalse(rows[3].tracked)
        // With nothing frozen apart, grouping matches tracking row for row.
        XCTAssertEqual(rows.map(\.grouped), rows.map { $0.isHub ? false : $0.tracked })
    }

    /// The Currencies page freezes `grouping` when it opens, so a currency toggled ON
    /// mid-visit keeps its position in the lower group while its switch reads ON.
    /// Ordering must follow the FROZEN set and `tracked` must follow the live one.
    func test_rows_frozenGrouping_keepsOrder_whileTrackedGoesLive() {
        let all = ["JPY", "EUR", "USD", "CAD", "AED"]
        let frozen = ["EUR"]                                  // as the screen opened
        let rows = fxCurrencyRows(all: all, rates: rates, tracked: ["EUR", "JPY"], grouping: frozen)

        // JPY was just switched on, but it stays down in the A–Z remainder.
        XCTAssertEqual(rows.map(\.code), ["USD", "EUR", "AED", "CAD", "JPY"])
        XCTAssertEqual(rows.map(\.grouped), [false, true, false, false, false])
        XCTAssertEqual(rows.map(\.tracked), [false, true, false, false, true])

        // Sections read `grouped`: JPY is NOT promoted until the screen reopens.
        XCTAssertEqual(rows.filter { $0.isHub || $0.grouped }.map(\.code), ["USD", "EUR"])
        XCTAssertEqual(rows.filter { !$0.isHub && !$0.grouped }.map(\.code), ["AED", "CAD", "JPY"])

        // Reopening thaws it: grouping catches up and JPY moves into the active group.
        let reopened = fxCurrencyRows(all: all, rates: rates, tracked: ["EUR", "JPY"], grouping: ["EUR", "JPY"])
        XCTAssertEqual(reopened.filter { $0.isHub || $0.grouped }.map(\.code), ["USD", "EUR", "JPY"])
    }

    /// Toggling OFF is symmetric — the row does not drop out of the active group
    /// under the finger that just switched it off.
    func test_rows_frozenGrouping_keepsPosition_whenTrackedGoesOff() {
        let rows = fxCurrencyRows(all: ["JPY", "EUR", "USD"], rates: rates,
                                  tracked: [], grouping: ["EUR", "JPY"])
        XCTAssertEqual(rows.map(\.code), ["USD", "EUR", "JPY"])
        XCTAssertEqual(rows.filter { $0.isHub || $0.grouped }.map(\.code), ["USD", "EUR", "JPY"])
        XCTAssertTrue(rows.allSatisfy { !$0.tracked })       // every switch reads OFF
    }

    /// The Currencies list shows the rate the engine converts with, not a newer
    /// derived copy, and nothing for a currency that has only copies.
    func test_rows_rateSkipsDerivedCopies() {
        let rows = fxCurrencyRows(all: ["KRW", "THB"], rates: [
            ExchangeRate(date: "2026-05-10", currency: "KRW", rate: 0.00073, source: "manual"),
            ExchangeRate(date: "2026-05-20", currency: "KRW", rate: 0.0073, source: "derived"),
            ExchangeRate(date: "2026-05-14", currency: "THB", rate: 1, source: "derived"),
        ], tracked: [], grouping: [])
        XCTAssertEqual(rows.first { $0.code == "KRW" }?.rate, 0.00073)
        XCTAssertNil(rows.first { $0.code == "THB" }?.rate)
    }

    func test_filter_byCodeOrName_caseInsensitive_orderPreserved() {
        let rows = fxCurrencyRows(all: ["JPY", "EUR", "USD", "CAD"], rates: rates,
                                  tracked: ["EUR"], grouping: ["EUR"])
        XCTAssertEqual(fxFilterRows(rows, query: "").map(\.code), rows.map(\.code))
        XCTAssertEqual(fxFilterRows(rows, query: "eur").map(\.code), ["EUR"])
        XCTAssertEqual(fxFilterRows(rows, query: "yen").map(\.code), ["JPY"])   // matches localized name
        XCTAssertTrue(fxFilterRows(rows, query: "zzzzz").isEmpty)
    }

    // MARK: activating a picked ledger base currency

    func test_activating_newCode_appendsSorted() {
        XCTAssertEqual(fxTrackedAfterActivating("CHF", tracked: ["EUR", "JPY"]), ["CHF", "EUR", "JPY"])
    }

    func test_activating_hubOrAlreadyTracked_needsNoWrite() {
        XCTAssertNil(fxTrackedAfterActivating("USD", tracked: ["EUR"]))          // hub is never tracked
        XCTAssertNil(fxTrackedAfterActivating("usd", tracked: []))               // …case-insensitively
        XCTAssertNil(fxTrackedAfterActivating("EUR", tracked: ["EUR", "JPY"]))   // already activated
        XCTAssertNil(fxTrackedAfterActivating("eur", tracked: ["EUR"]))          // …case-insensitively
        XCTAssertNil(fxTrackedAfterActivating("   ", tracked: ["EUR"]))          // nothing picked
    }

    func test_activating_normalizesCaseAndWhitespace() {
        XCTAssertEqual(fxTrackedAfterActivating("  chf ", tracked: ["eur"]), ["CHF", "EUR"])
    }

    /// The empty-but-explicit tracked set must still take the write — that is what
    /// distinguishes "user untracked everything" from "no key yet" upstream.
    func test_activating_fromEmptyTrackedSet_writes() {
        XCTAssertEqual(fxTrackedAfterActivating("GBP", tracked: []), ["GBP"])
    }
}

/// The store's conversions and its display-currency choices, over a database that
/// still holds `'derived'` copies older versions saved.
@MainActor
final class DerivedRateDisplayTests: XCTestCase {
    private func loaded() async throws -> FinchStore {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: url))
        return store
    }

    private func setRate(_ store: FinchStore, _ day: String, _ currency: String,
                         _ rate: Double, _ source: String) throws {
        try store.apply(.setExchangeRate, Args([
            "date": .string(day), "currency": .string(currency), "rate": .double(rate), "source": .string(source)]))
    }

    /// The reported problem: KRW's rate was corrected by hand, but a newer derived
    /// copy of the mistyped one still converted every KRW balance on screen.
    func test_conversionsUseTheCorrectedRate_notANewerDerivedCopy() async throws {
        let store = try await loaded()
        try setRate(store, "2026-05-10", "KRW", 0.00073, "manual")
        try setRate(store, "2026-05-20", "KRW", 0.0073, "derived")
        XCTAssertEqual(store.rateMap["KRW"] ?? 0, 0.00073, accuracy: 1e-12)
        XCTAssertEqual(Money.convert(50_000, from: "KRW", to: "USD", rates: store.rateMap) ?? 0, 36.5, accuracy: 1e-6)
    }

    /// A currency with only derived copies has no rate, so it is not offered as a
    /// display currency: nothing would convert into it.
    func test_aCurrencyWithOnlyDerivedRows_isNotADisplayChoice() async throws {
        let store = try await loaded()
        try setRate(store, "2026-05-14", "THB", 1, "derived")
        XCTAssertNil(store.rateMap["THB"])
        XCTAssertFalse(store.availableDisplayCurrencies.contains("THB"))
        XCTAssertFalse(store.availableDisplayCurrencies(forLedger: store.activeLedgerId).contains("THB"))
    }
}
