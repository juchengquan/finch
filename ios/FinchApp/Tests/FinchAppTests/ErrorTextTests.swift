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

    /// Refusing to skip a posted occurrence names it, as the English does, and says
    /// 记账 like the neighbouring scheduled errors rather than 发布.
    func test_zh_skipAlreadyPosted_namesTheItemAndDate() {
        let e = I18nError("error.scheduled.skipAlreadyPosted", ["name": "Gym", "date": "2026-04-15"],
                          "\"Gym\" was already posted for 2026-04-15")
        let s = i18nMessage(e, zh: true)
        XCTAssertTrue(s.contains("Gym") && s.contains("2026-04-15"), s)
        XCTAssertTrue(s.contains("记账"), s)
        XCTAssertFalse(s.contains("发布"), s)
    }

    func test_zh_withoutAnEntry_fallsBackToEnglish() {
        let e = I18nError("error.not.a.code", [:], "Fallback")
        XCTAssertEqual(i18nMessage(e, zh: true), "Fallback")
    }
}
