import XCTest
@testable import FinchApp

final class InsightsLayoutTests: XCTestCase {
    func test_defaultLayout_isOverview() {
        XCTAssertEqual(InsightsLayout.default.order, InsightsTemplate.overview.cardIDs)
        XCTAssertEqual(InsightsLayout.default.templateName, InsightsTemplate.overview.rawValue)
    }
    func test_catalogIDs_areUnique() {
        let ids = InsightsCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
    func test_everyTemplateID_existsInCatalog() {
        let catalog = Set(InsightsCatalog.all.map(\.id))
        for t in InsightsTemplate.allCases {
            for id in t.cardIDs { XCTAssertTrue(catalog.contains(id), "\(t.rawValue): unknown id \(id)") }
        }
    }
    func test_rawRepresentable_roundTrips() {
        let l = InsightsLayout(order: ["netWorth", "cashflow"], templateName: nil)
        XCTAssertEqual(InsightsLayout(rawValue: l.rawValue), l)
    }
    func test_matchingTemplate_detectsPresetVsCustom() {
        XCTAssertEqual(InsightsLayout(order: InsightsTemplate.wealth.cardIDs, templateName: nil).matchingTemplate(), .wealth)
        XCTAssertNil(InsightsLayout(order: ["netWorth"], templateName: nil).matchingTemplate())
    }
}
