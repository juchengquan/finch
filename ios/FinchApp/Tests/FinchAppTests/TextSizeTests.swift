import XCTest
import SwiftUI
@testable import FinchApp

final class TextSizeTests: XCTestCase {
    func test_stepMapping_andClamping() {
        XCTAssertEqual(TextSize.steps.count, 7)
        XCTAssertEqual(TextSize.size(forStep: 0), .xSmall)
        XCTAssertEqual(TextSize.size(forStep: 3), .large)
        XCTAssertEqual(TextSize.size(forStep: 6), .xxxLarge)
        XCTAssertEqual(TextSize.size(forStep: -5), .xSmall)
        XCTAssertEqual(TextSize.size(forStep: 99), .xxxLarge)
        XCTAssertEqual(TextSize.defaultStep, 3)
    }
}
