import XCTest
@testable import FinchApp

final class SavedSearchStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "test.savedsearch.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_save_and_all_scoped_per_ledger() {
        let s = SavedSearchStore(defaults: freshDefaults())
        s.save(name: "Dining", filter: TxFilter(categoryId: "c1"), ledgerId: "l1")
        s.save(name: "Other", filter: TxFilter(direction: "out"), ledgerId: "l2")
        XCTAssertEqual(s.all(ledgerId: "l1").map(\.name), ["Dining"])
        XCTAssertEqual(s.all(ledgerId: "l2").map(\.name), ["Other"])
    }

    func test_remove() {
        let s = SavedSearchStore(defaults: freshDefaults())
        s.save(name: "A", filter: TxFilter(status: "pending"), ledgerId: "l1")
        s.remove(s.all(ledgerId: "l1")[0].id)
        XCTAssertTrue(s.all(ledgerId: "l1").isEmpty)
    }

    func test_empty_name_ignored() {
        let s = SavedSearchStore(defaults: freshDefaults())
        s.save(name: "   ", filter: TxFilter(status: "pending"), ledgerId: "l1")
        XCTAssertTrue(s.all(ledgerId: "l1").isEmpty)
    }

    func test_persists_across_instances() {
        let name = "test.savedsearch.persist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name)
        SavedSearchStore(defaults: d).save(name: "Keep", filter: TxFilter(minAmount: 50), ledgerId: "l1")
        XCTAssertEqual(SavedSearchStore(defaults: d).all(ledgerId: "l1").map(\.name), ["Keep"])
    }

    func test_txfilter_codable_roundtrip() throws {
        var f = TxFilter()
        f.direction = "out"; f.categoryId = "c1"; f.tagIds = ["t1", "t2"]; f.tagsMatchAll = true
        f.status = "pending"; f.from = Date(timeIntervalSince1970: 1_700_000_000)
        f.to = Date(timeIntervalSince1970: 1_700_100_000); f.minAmount = 5; f.maxAmount = 500
        let back = try JSONDecoder().decode(TxFilter.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }
}
