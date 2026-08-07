import XCTest
@testable import FinchCore

/// Pins the Swift ISO 4217 minor-units table to the web's
/// (frontend/lib/currency.ts, exported by export-fixtures.ts). The table is
/// checked in twice — once per front-end — precisely so neither side reads
/// platform ICU data; this gate is what keeps the two copies from drifting.
final class CurrencyParityTests: XCTestCase {

    func test_minor_unit_exceptions_match_the_web_table() throws {
        let fixtures = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let url = fixtures.appendingPathComponent("currency-minor-units.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return XCTFail("currency-minor-units.json missing — run: cd frontend && bun scripts/export-fixtures.ts")
        }
        let web = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))
        XCTAssertEqual(web, Currencies.minorUnitExceptions,
                       "the Swift exceptions table and the web table disagree")
    }
}
