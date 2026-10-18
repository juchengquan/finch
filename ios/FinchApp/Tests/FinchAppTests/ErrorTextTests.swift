import XCTest
import FinchCore
@testable import FinchApp

/// `i18nMessage` is what every write screen shows for a refused write.
final class ErrorTextTests: XCTestCase {
    private let noRate = I18nError("error.fx.noRate", ["from": "KRW", "to": "USD", "currency": "KRW"],
                                   "No exchange rate for KRW → USD yet. Enter a KRW rate by hand in Settings › Currencies, or turn KRW on there and tap Refresh now.")

    func test_english_isTheEngineMessage() {
        XCTAssertEqual(i18nMessage(noRate, zh: false), noRate.message)
    }

    /// The zh string names the pair: placeholders are filled, not shown as braces.
    func test_zh_fillsThePlaceholders() {
        let s = i18nMessage(noRate, zh: true)
        XCTAssertTrue(s.contains("KRW → USD"), s)
        XCTAssertFalse(s.contains("{"), s)
    }

    func test_zh_withoutAnEntry_fallsBackToEnglish() {
        let e = I18nError("error.not.a.code", [:], "Fallback")
        XCTAssertEqual(i18nMessage(e, zh: true), "Fallback")
    }
}
