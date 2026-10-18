import XCTest
@testable import FinchApp
import FinchCore

/// How a stored USD-per-unit rate reads on the Currencies list and the history.
/// "%.4f" printed KRW as "0.0007" and left the direction unsaid; these pin the
/// sentence, its direction rule, and its precision across the range of unit sizes.
final class FxRateDisplayTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    /// A small-unit currency reads the other way round, with its digits intact.
    func test_krw_readsInvertedWithItsDigits() {
        XCTAssertEqual(fxRateDisplay(0.00073, currency: "KRW", locale: en), "1 USD = 1,369.86 KRW")
    }

    func test_jpy_readsInverted() {
        XCTAssertEqual(fxRateDisplay(0.0063, currency: "JPY", locale: en), "1 USD = 158.73 JPY")
    }

    /// The very smallest units keep six digits rather than rounding to "0.0000".
    func test_idrAndVnd_keepSixDigits() {
        XCTAssertEqual(fxRateDisplay(0.0000616, currency: "IDR", locale: en), "1 USD = 16,233.8 IDR")
        XCTAssertEqual(fxRateDisplay(0.0000393, currency: "VND", locale: en), "1 USD = 25,445.3 VND")
    }

    /// A currency worth more than a dollar reads the way it is stored.
    func test_eur_readsAsStored() {
        XCTAssertEqual(fxRateDisplay(1.0842, currency: "EUR", locale: en), "1 EUR = 1.0842 USD")
    }

    /// A very large unit keeps its fifth and sixth digits.
    func test_kwd_largeUnit() {
        XCTAssertEqual(fxRateDisplay(3.25411, currency: "KWD", locale: en), "1 KWD = 3.25411 USD")
    }

    /// Exactly 1 is not under a dollar, so it reads as stored, at four digits.
    func test_pegged_one() {
        XCTAssertFalse(fxReadsInverted(latest: 1.0))
        XCTAssertEqual(fxRateDisplay(1.0, currency: "PAB", locale: en), "1 PAB = 1.000 USD")
    }

    /// The hub has no rate of its own to show.
    func test_usd_hasNoRate() {
        XCTAssertNil(fxRateDisplay(1.0, currency: "USD", locale: en))
    }

    /// A history keeps one direction: an older figure on the far side of 1 still
    /// reads the way the latest does.
    func test_explicitDirection_isKeptForEveryRow() {
        XCTAssertEqual(fxRateDisplay(0.98, currency: "CHF", inverted: false, locale: en), "1 CHF = 0.9800 USD")
        XCTAssertEqual(fxRateDisplay(1.25, currency: "CAD", inverted: true, locale: en), "1 USD = 0.8000 CAD")
    }

    /// Grouping and the decimal mark follow the locale.
    func test_number_isLocaleAware() {
        XCTAssertEqual(fxRateNumber(1369.863, locale: Locale(identifier: "de_DE")), "1.369,86")
        XCTAssertEqual(fxRateNumber(1369.863, locale: Locale(identifier: "zh_Hans_CN")), "1,369.86")
        XCTAssertEqual(fxRateNumber(1.0842, locale: Locale(identifier: "fr_FR")), "1,0842")
    }

    /// The sparkline turns over with the rows, so it rises when their figures do.
    func test_series_followsTheRowsDirection() {
        let rates = [
            ExchangeRate(date: "2026-05-01", currency: "KRW", rate: 0.0008, source: "ECB"),
            ExchangeRate(date: "2026-06-01", currency: "KRW", rate: 0.0005, source: "ECB"),
            ExchangeRate(date: "2026-05-01", currency: "EUR", rate: 1.1, source: "ECB"),
            ExchangeRate(date: "2026-06-01", currency: "EUR", rate: 1.2, source: "ECB"),
        ]
        let krw = fxDisplaySeries(rates, "KRW")
        XCTAssertEqual(krw[0], 1250, accuracy: 1e-9)
        XCTAssertEqual(krw[1], 2000, accuracy: 1e-9)
        XCTAssertEqual(fxDisplaySeries(rates, "EUR"), [1.1, 1.2])
    }
}
