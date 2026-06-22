import XCTest
@testable import FinchApp

/// Phase 3 — the pure command-palette catalogue + filter (⌘K).
final class CommandPaletteTests: XCTestCase {
    func test_catalogueCoversTabsPlusActions() {
        let titles = paletteCommands().map(\.title)
        // 7 "Go to <tab>" (incl. Ledger) + New Transaction.
        XCTAssertEqual(titles.filter { $0.hasPrefix("Go to ") }.count, 7)
        XCTAssertTrue(titles.contains("New Transaction"))
    }

    func test_filterByQuery() {
        let all = paletteCommands()
        XCTAssertEqual(filterPalette(all, query: "").count, all.count)        // empty → all
        XCTAssertEqual(filterPalette(all, query: "budget").map(\.title), ["Go to Budgets"])
        XCTAssertEqual(filterPalette(all, query: "  TRANSACTION ").map(\.title), ["New Transaction"]) // trim + case-insensitive
        XCTAssertTrue(filterPalette(all, query: "zzz").isEmpty)
    }
}
