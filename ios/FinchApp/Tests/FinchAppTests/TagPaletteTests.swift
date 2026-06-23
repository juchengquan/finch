import XCTest
@testable import FinchApp

final class TagPaletteTests: XCTestCase {
    func test_palette_has_eight_and_default() {
        XCTAssertEqual(TagPalette.hexes.count, 8)
        XCTAssertEqual(TagPalette.defaultHex, "#00a5da")
        XCTAssertTrue(TagPalette.hexes.contains(TagPalette.defaultHex))
    }

    func test_palette_matches_web_tag_hexes() {
        XCTAssertEqual(TagPalette.hexes,
            ["#e75572", "#e65f2a", "#ba8600", "#00af67", "#00adba", "#00a5da", "#7d7df9", "#be64d2"])
    }
}
