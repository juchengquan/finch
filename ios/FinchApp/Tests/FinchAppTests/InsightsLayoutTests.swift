import XCTest
@testable import FinchApp

final class InsightsLayoutTests: XCTestCase {
    private var catalog: [String] { InsightsCatalog.all.map(\.id) }

    func test_default_showsTheCuratedStarter_andHidesTheRest() {
        let d = InsightsLayout.default
        XCTAssertEqual(d.shownOrder, InsightsLayout.defaultShown)          // shown, in the curated order
        XCTAssertEqual(Array(d.order.prefix(InsightsLayout.defaultShown.count)), InsightsLayout.defaultShown)
        XCTAssertEqual(Set(d.order), Set(catalog))                         // all cards present + reorderable
        XCTAssertEqual(d.hidden, Set(catalog).subtracting(InsightsLayout.defaultShown))
    }

    func test_catalogIDs_areUnique() {
        XCTAssertEqual(catalog.count, Set(catalog).count)
    }

    func test_defaultShown_idsAllExistInCatalog() {
        for id in InsightsLayout.defaultShown { XCTAssertTrue(catalog.contains(id), "unknown default id \(id)") }
    }

    func test_init_normalizesToCatalog_dropsUnknown_appendsNew() {
        // Unknown "ghost" dropped; catalog cards missing from `order` appended (shown).
        let l = InsightsLayout(order: ["netWorth", "ghost"], hidden: ["ghost"])
        XCTAssertEqual(Set(l.order), Set(catalog))                        // exactly the catalog
        XCTAssertEqual(l.order.first, "netWorth")                         // user order preserved up front
        XCTAssertFalse(l.hidden.contains("ghost"))                        // unknown id clamped out
        XCTAssertTrue(l.shownOrder.contains("netWorth"))
    }

    func test_rawRepresentable_roundTrips() {
        let l = InsightsLayout(order: catalog, hidden: ["cashflow", "whatIf"])
        let decoded = InsightsLayout(rawValue: l.rawValue)
        XCTAssertEqual(decoded?.order, l.order)
        XCTAssertEqual(decoded?.hidden, l.hidden)
    }

    func test_legacyLayout_migrates_omittedIdsBecomeHidden() {
        // Old shape: `order` held only the shown ids, no `hidden` key.
        let legacy = #"{"order":["netWorth","cashflow"]}"#
        let l = InsightsLayout(rawValue: legacy)
        XCTAssertNotNil(l)
        XCTAssertEqual(l?.shownOrder, ["netWorth", "cashflow"])           // shown set preserved
        XCTAssertEqual(l?.hidden, Set(catalog).subtracting(["netWorth", "cashflow"]))
        XCTAssertEqual(Set(l?.order ?? []), Set(catalog))                 // all cards now in order
    }

    func test_corruptRawValue_returnsNil_soAppStorageFallsBackToDefault() {
        XCTAssertNil(InsightsLayout(rawValue: "not json"))
    }
}
