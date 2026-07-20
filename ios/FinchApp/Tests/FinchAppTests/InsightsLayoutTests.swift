import XCTest
@testable import FinchApp

final class InsightsLayoutTests: XCTestCase {
    func test_defaultLayout_isTheCuratedStarter() {
        XCTAssertEqual(InsightsLayout.default.order, InsightsLayout.defaultOrder)
    }
    func test_defaultOrder_idsAllExistInCatalog() {
        let catalog = Set(InsightsCatalog.all.map(\.id))
        for id in InsightsLayout.defaultOrder { XCTAssertTrue(catalog.contains(id), "unknown default id \(id)") }
    }
    func test_catalogIDs_areUnique() {
        let ids = InsightsCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
    func test_rawRepresentable_roundTrips() {
        let l = InsightsLayout(order: ["netWorth", "cashflow"])
        XCTAssertEqual(InsightsLayout(rawValue: l.rawValue), l)
    }
    func test_corruptRawValue_returnsNil_soAppStorageFallsBackToDefault() {
        XCTAssertNil(InsightsLayout(rawValue: "not json"))
    }
}
