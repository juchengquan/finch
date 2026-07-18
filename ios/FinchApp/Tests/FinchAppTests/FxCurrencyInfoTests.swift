import XCTest
@testable import FinchApp

/// Localized currency names + signs (cached). @MainActor per suite idiom.
@MainActor
final class FxCurrencyInfoTests: XCTestCase {
    func test_name_localizedWithCodeFallback() {
        XCTAssertNotEqual(FxCurrencyInfo.name("EUR"), "EUR")   // a real localized name exists
        XCTAssertEqual(FxCurrencyInfo.name("ZZZ"), "ZZZ")      // bogus code falls back to itself
    }
    func test_symbol_shortestDistinct_orNil() {
        XCTAssertEqual(FxCurrencyInfo.symbol("USD"), "$")
        XCTAssertEqual(FxCurrencyInfo.symbol("EUR"), "€")
        XCTAssertNil(FxCurrencyInfo.symbol("ZZZ"))
    }
    func test_label_composition_andRepeatIsCached() {
        XCTAssertEqual(FxCurrencyInfo.label("EUR"), "\(FxCurrencyInfo.name("EUR")) (€)")
        XCTAssertEqual(FxCurrencyInfo.label("ZZZ"), "ZZZ")     // no bracket without a distinct symbol
        XCTAssertNotNil(FxCurrencyInfo.labelCache["EUR"])   // first call memoized
        XCTAssertEqual(FxCurrencyInfo.label("EUR"), FxCurrencyInfo.label("EUR"))
    }
}
