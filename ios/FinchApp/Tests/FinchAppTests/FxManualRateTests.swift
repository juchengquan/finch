import XCTest
@testable import FinchApp
import FinchCore

/// The hand-entered rate form's arithmetic: what it asks ("1 KRW = ___ EUR") and the
/// USD-per-unit figure it stores. A direction mix-up here books every KRW amount
/// a million times too large or small, so each direction is pinned both ways.
final class FxManualRateTests: XCTestCase {
    private let rates = [
        ExchangeRate(date: "2026-05-01", currency: "EUR", rate: 1.10, source: "ECB"),
        ExchangeRate(date: "2026-06-01", currency: "EUR", rate: 1.20, source: "ECB"),
    ]

    /// A USD ledger quotes against USD, and the typed figure IS the stored one.
    func test_usdBase_storesWhatWasTyped() {
        let q = FxManualQuote.make(currency: "KRW", base: "USD", date: "2026-05-09", rates: rates)
        XCTAssertEqual(q.quote, "USD")
        XCTAssertEqual(q.terms(inverted: false).one, "KRW")
        XCTAssertEqual(q.usdPerUnit(entered: 0.00073, inverted: false)!, 0.00073, accuracy: 1e-12)
    }

    /// Flipped, "1 USD = 1370 KRW" stores 1/1370 USD per KRW.
    func test_inverted_storesTheReciprocal() {
        let q = FxManualQuote.make(currency: "KRW", base: "USD", date: "2026-05-09", rates: rates)
        XCTAssertEqual(q.terms(inverted: true).one, "USD")
        XCTAssertEqual(q.terms(inverted: true).other, "KRW")
        XCTAssertEqual(q.usdPerUnit(entered: 1370, inverted: true)!, 1 / 1370.0, accuracy: 1e-12)
    }

    /// A EUR ledger asks in EUR, pivoting through the EUR rate in force on the
    /// rate's date — the one the engine would use for a write that day.
    func test_eurBase_pivotsThroughTheBaseRateOnThatDate() {
        let may = FxManualQuote.make(currency: "KRW", base: "EUR", date: "2026-05-09", rates: rates)
        XCTAssertEqual(may.quote, "EUR")
        XCTAssertEqual(may.usdPerQuote, 1.10)
        XCTAssertEqual(may.usdPerUnit(entered: 0.0007, inverted: false)!, 0.00077, accuracy: 1e-12)
        let june = FxManualQuote.make(currency: "KRW", base: "EUR", date: "2026-06-15", rates: rates)
        XCTAssertEqual(june.usdPerQuote, 1.20)
        // Before the first EUR rate, the nearest one after is used.
        XCTAssertEqual(FxManualQuote.make(currency: "KRW", base: "EUR", date: "2026-01-01", rates: rates).usdPerQuote, 1.10)
    }

    /// A base with no rate cannot carry the quote, so the form asks against USD.
    func test_unratedBase_fallsBackToUSD() {
        let q = FxManualQuote.make(currency: "KRW", base: "THB", date: "2026-05-09", rates: rates)
        XCTAssertEqual(q.quote, "USD")
        XCTAssertEqual(q.usdPerQuote, 1)
    }

    /// Rating the base itself (a KRW ledger whose base has no rate) asks against USD,
    /// never "1 KRW = ___ KRW".
    func test_ratingTheBaseItself_asksAgainstUSD() {
        let q = FxManualQuote.make(currency: "KRW", base: "KRW", date: "2026-05-09", rates: rates)
        XCTAssertEqual(q.quote, "USD")
    }

    /// Editing seeds the field with the figure that saves back unchanged.
    func test_entered_roundTrips() {
        let q = FxManualQuote.make(currency: "KRW", base: "EUR", date: "2026-05-09", rates: rates)
        for inverted in [false, true] {
            let typed = q.entered(usdPerUnit: 0.00077, inverted: inverted)
            XCTAssertEqual(q.usdPerUnit(entered: typed, inverted: inverted)!, 0.00077, accuracy: 1e-12)
        }
        XCTAssertEqual(q.entered(usdPerUnit: 0.00077, inverted: false), 0.0007, accuracy: 1e-12)
    }

    func test_nonPositive_isNoRate() {
        let q = FxManualQuote.make(currency: "KRW", base: "USD", date: "2026-05-09", rates: rates)
        XCTAssertNil(q.usdPerUnit(entered: 0, inverted: false))
        XCTAssertNil(q.usdPerUnit(entered: -1, inverted: true))
        XCTAssertNil(q.usdPerUnit(entered: 0, inverted: true))
    }

    func test_rateText_isPlainAndShort() {
        XCTAssertEqual(fxRateText(0.00073), "0.00073")
        XCTAssertEqual(fxRateText(1369.863013), "1369.86")
        XCTAssertEqual(fxRateText(0.0000393), "0.0000393")
        XCTAssertEqual(fxRateText(1.1), "1.1")
        XCTAssertEqual(DecimalInput.parse(fxRateText(0.0000393)), 0.0000393)
    }

    func test_manualOnlyForHandEnteredRows() {
        XCTAssertTrue(fxIsManual(ExchangeRate(date: "2026-05-01", currency: "KRW", rate: 1, source: "manual")))
        XCTAssertTrue(fxIsManual(ExchangeRate(date: "2026-05-01", currency: "KRW", rate: 1, source: nil)))
        XCTAssertFalse(fxIsManual(ExchangeRate(date: "2026-05-01", currency: "KRW", rate: 1, source: "ECB")))
        XCTAssertFalse(fxIsManual(ExchangeRate(date: "2026-05-01", currency: "KRW", rate: 1, source: "derived")))
    }

    /// The refusal names the currency to enter, so the sheet can open on it.
    func test_noRateCurrency_readsTheRefusal() {
        let e = I18nError("error.fx.noRate", ["from": "USD", "to": "KRW", "currency": "KRW"], "x")
        XCTAssertEqual(fxNoRateCurrency(e), "KRW")
        XCTAssertNil(fxNoRateCurrency(I18nError("error.fx.rateGt0", [:], "x")))
        XCTAssertNil(fxNoRateCurrency(NSError(domain: "x", code: 1)))
    }

    /// The offer stays with the refusal it was made for: once the sheet shows any
    /// other error, "Enter a KRW rate" no longer applies.
    func test_refusal_isOnlyOfferedUnderItsOwnMessage() {
        let e = I18nError("error.fx.noRate", ["from": "KRW", "to": "USD", "currency": "KRW"], "No KRW rate")
        let r = FxNoRateRefusal(e, shown: "No KRW rate")
        XCTAssertEqual(r?.currency, "KRW")
        XCTAssertTrue(r?.isShowing("No KRW rate") == true)
        XCTAssertFalse(r?.isShowing("Enter an amount.") == true)
        XCTAssertFalse(r?.isShowing(nil) == true)
        XCTAssertNil(FxNoRateRefusal(I18nError("error.fx.rateGt0", [:], "x"), shown: "x"))
    }
}
