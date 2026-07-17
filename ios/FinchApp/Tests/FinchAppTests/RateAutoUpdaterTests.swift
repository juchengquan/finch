import XCTest
@testable import FinchApp

/// RateAutoUpdater's pure pieces (no network in tests). The enum is @MainActor,
/// so the class is @MainActor too (suite idiom — see DeepLinkRouterTests).
@MainActor
final class RateAutoUpdaterTests: XCTestCase {
    func test_parse_invertsQuotePerUSD_dropsUSDAndInvalid() throws {
        let json = #"[{"date":"2026-07-17","base":"USD","quote":"EUR","rate":0.87241},{"date":"2026-07-17","base":"USD","quote":"USD","rate":1},{"date":"2026-07-17","base":"USD","quote":"BAD","rate":0}]"#
        let rows = RateAutoUpdater.parse(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].currency, "EUR")
        XCTAssertEqual(rows[0].ratePerUSD, 1.146250, accuracy: 0.000001)   // 1/0.87241, 6-dp
    }
    func test_parse_malformed_returnsEmpty() {
        XCTAssertTrue(RateAutoUpdater.parse(Data("nope".utf8)).isEmpty)
    }
    func test_isDue_throttle() {
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: nil))
        XCTAssertFalse(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-3600)))
        XCTAssertTrue(RateAutoUpdater.isDue(now: Date(), last: Date().addingTimeInterval(-21*3600)))
    }
}
