import XCTest
@testable import FinchApp

/// RateAutoUpdater's pure pieces (no network in tests). The enum is @MainActor,
/// so the class is @MainActor too (suite idiom — see DeepLinkRouterTests).
@MainActor
final class RateAutoUpdaterTests: XCTestCase {
    // MARK: Frankfurter (provider 1)
    func test_frankfurter_invertsQuotePerUSD_dropsUSDAndInvalid() throws {
        let json = #"[{"date":"2026-07-17","base":"USD","quote":"EUR","rate":0.87241},{"date":"2026-07-17","base":"USD","quote":"USD","rate":1},{"date":"2026-07-17","base":"USD","quote":"BAD","rate":0}]"#
        let rows = RateAutoUpdater.parseFrankfurter(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].currency, "EUR")
        XCTAssertEqual(rows[0].ratePerUSD, 1.146250, accuracy: 0.000001)   // 1/0.87241, 6-dp
    }
    func test_frankfurter_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parseFrankfurter(Data("nope".utf8)).isEmpty)
    }

    // MARK: open.er-api.com (provider 2) — filters to requested codes, uppercase output.
    func test_erApi_filtersToCodes_invertsAndDropsUSDInvalid() throws {
        let json = #"{"time_last_update_unix":1721260801,"rates":{"USD":1,"EUR":0.87241,"JPY":155.0,"BAD":0}}"#
        let rows = RateAutoUpdater.parseErApi(Data(json.utf8), codes: ["EUR", "JPY"]).sorted { $0.currency < $1.currency }
        XCTAssertEqual(rows.map(\.currency), ["EUR", "JPY"])               // USD + BAD dropped; codes-only
        XCTAssertEqual(rows[0].ratePerUSD, 1.146250, accuracy: 0.000001)   // 1/0.87241
        XCTAssertEqual(rows[1].ratePerUSD, 1.0 / 155.0, accuracy: 0.000001)
    }
    func test_erApi_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parseErApi(Data("nope".utf8), codes: ["EUR"]).isEmpty)
    }

    // MARK: fawazahmed0 currency-api (provider 3) — lowercase keys → uppercase output.
    func test_currencyApi_filtersUppercases_invertsAndDropsUSD() throws {
        let json = #"{"date":"2026-07-17","usd":{"eur":0.87241,"jpy":155.0,"usd":1}}"#
        let rows = RateAutoUpdater.parseCurrencyApi(Data(json.utf8), codes: ["EUR"])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].currency, "EUR")                            // lowercased key → uppercased out
        XCTAssertEqual(rows[0].date, "2026-07-17")
        XCTAssertEqual(rows[0].ratePerUSD, 1.146250, accuracy: 0.000001)
    }
    func test_currencyApi_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parseCurrencyApi(Data("nope".utf8), codes: ["EUR"]).isEmpty)
    }

    func test_isDue_throttle() {
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: nil))
        XCTAssertFalse(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-3600)))
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-21*3600)))
    }
}
