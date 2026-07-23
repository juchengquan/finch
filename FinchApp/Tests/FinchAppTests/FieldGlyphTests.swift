import XCTest
import SwiftUI
@testable import FinchApp

final class FieldGlyphTests: XCTestCase {
    func testSymbolsAreStableAndNonEmpty() {
        // A representative mapping — the vocabulary must be deterministic.
        XCTAssertEqual(FieldGlyph.account.symbol, "building.columns")
        XCTAssertEqual(FieldGlyph.amount.symbol, "dollarsign.circle")
        XCTAssertEqual(FieldGlyph.category.symbol, "folder")
        XCTAssertEqual(FieldGlyph.date.symbol, "calendar")
        XCTAssertEqual(FieldGlyph.merchant.symbol, "storefront")
        XCTAssertEqual(FieldGlyph.tags.symbol, "tag")
        XCTAssertEqual(FieldGlyph.status.symbol, "checkmark.circle")
    }
    func testFromAndToAreDistinct() {
        XCTAssertNotEqual(FieldGlyph.fromAccount.symbol, FieldGlyph.toAccount.symbol)
    }
    func testFrequencyAndDateAreDistinct() {
        XCTAssertNotEqual(FieldGlyph.frequency.symbol, FieldGlyph.date.symbol)
    }
    func testEveryCaseHasANonEmptySymbol() {
        let all: [FieldGlyph] = [.account,.fromAccount,.toAccount,.amount,.category,.date,
            .merchant,.note,.status,.tags,.receipt,.refund,.name,.group,.frequency,.currency,.color,.icon]
        for g in all { XCTAssertFalse(g.symbol.isEmpty, "\(g) has empty symbol") }
    }
}
