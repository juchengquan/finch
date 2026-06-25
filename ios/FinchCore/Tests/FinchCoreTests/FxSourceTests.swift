import XCTest
@testable import FinchCore

final class FxSourceTests: XCTestCase {
    func test_projection_carries_source() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-01"), "currency": .string("EUR"), "rate": .double(1.1), "source": .string("ECB")]))
        try Apply.apply(dbQueue: q, action: "setExchangeRate", args: Args([
            "date": .string("2026-05-01"), "currency": .string("JPY"), "rate": .double(0.0064)]))   // no source
        let rates = try Projection.exchangeRates(dbQueue: q)
        XCTAssertEqual(try XCTUnwrap(rates.first { $0.currency == "EUR" }).source, "ECB")
        XCTAssertNil(try XCTUnwrap(rates.first { $0.currency == "JPY" }).source)
    }

    func test_currencies_iso_sane() {
        XCTAssertFalse(Currencies.iso.isEmpty)
        for c in ["EUR", "JPY", "BRL", "USD"] { XCTAssertTrue(Currencies.iso.contains(c), "missing \(c)") }
        XCTAssertEqual(Currencies.iso, Currencies.iso.sorted(), "must be sorted")
        XCTAssertEqual(Set(Currencies.iso).count, Currencies.iso.count, "must be unique")
    }
}
