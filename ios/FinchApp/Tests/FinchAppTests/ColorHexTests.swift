import XCTest
import SwiftUI
@testable import FinchApp

final class ColorHexTests: XCTestCase {
    func test_parses_rrggbb_with_hash() {
        let c = Color.rgb(fromHex: "#00a0c5")
        XCTAssertNotNil(c)
        XCTAssertEqual(c!.r, 0.0, accuracy: 0.001)
        XCTAssertEqual(c!.g, 160.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c!.b, 197.0 / 255.0, accuracy: 0.001)
    }

    func test_parses_without_hash() {
        XCTAssertNotNil(Color.rgb(fromHex: "ffffff"))
    }

    func test_rejects_malformed() {
        XCTAssertNil(Color.rgb(fromHex: "#fff"))      // too short
        XCTAssertNil(Color.rgb(fromHex: "#zzzzzz"))   // non-hex
        XCTAssertNil(Color.rgb(fromHex: ""))
    }

    func test_palette_has_eight_and_default() {
        XCTAssertEqual(CategoryPalette.hexes.count, 8)
        XCTAssertEqual(CategoryPalette.defaultHex, "#00a0c5")
        XCTAssertTrue(CategoryPalette.hexes.contains(CategoryPalette.defaultHex))
    }
}
