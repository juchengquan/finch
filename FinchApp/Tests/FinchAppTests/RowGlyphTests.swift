import XCTest
@testable import FinchApp

/// Which glyph a transaction-shaped row draws at its leading edge.
///
/// `TxRow` and `ScheduledRow` both call this, and they are deliberately matched so the
/// two lists scan alike — so a change that suits one and not the other shows up here
/// rather than on screen.
final class RowGlyphTests: XCTestCase {

    // MARK: Kind wins

    /// Transfers and adjustments are category-less BY NATURE — a transfer moves money
    /// between the user's own accounts, an adjustment is booked by the engine. They get
    /// a glyph that says what they are, and they keep it even on the rare row that does
    /// carry a category, so a transfer always reads as a transfer.
    func test_transfer_usesItsOwnGlyph_evenWithACategory() {
        let g = RowGlyph.resolve(kind: "transfer", categoryIcon: "cart", categoryColorHex: "#FF0000")
        XCTAssertEqual(g, RowGlyph.Glyph(symbol: "arrow.left.arrow.right", tint: .kind))
    }

    func test_adjustment_usesItsOwnGlyph() {
        let g = RowGlyph.resolve(kind: "adjustment", categoryIcon: nil, categoryColorHex: nil)
        XCTAssertEqual(g, RowGlyph.Glyph(symbol: "slider.horizontal.3", tint: .kind))
    }

    // MARK: Category

    func test_category_usesItsIconAndColour() {
        let g = RowGlyph.resolve(kind: "expense", categoryIcon: "cart", categoryColorHex: "#3366FF")
        XCTAssertEqual(g, RowGlyph.Glyph(symbol: CategoryIcon.symbol(for: "cart"),
                                         tint: .category(hex: "#3366FF")))
        XCTAssertNotEqual(g.symbol, "tag.fill", "a named icon must not fall back")
    }

    /// A category whose chain sets no icon still belongs to that category, so it keeps
    /// the category TINT and only the symbol falls back. Tinting it `.unset` here would
    /// make a real category look unassigned.
    func test_categoryWithNoIcon_keepsCategoryTint_symbolFallsBack() {
        let g = RowGlyph.resolve(kind: "expense", categoryIcon: nil, categoryColorHex: "#3366FF")
        XCTAssertEqual(g.symbol, "tag.fill")
        XCTAssertEqual(g.tint, .category(hex: "#3366FF"))
    }

    // MARK: No category

    /// Colour, not icon, is the presence test: `effectiveColor` always resolves for a
    /// real category (palette default), so a nil colour means exactly "no category".
    func test_uncategorisedExpense_isGreyTag() {
        let g = RowGlyph.resolve(kind: "expense", categoryIcon: nil, categoryColorHex: nil)
        XCTAssertEqual(g, RowGlyph.Glyph(symbol: "tag.fill", tint: .unset))
    }

    func test_uncategorisedIncome_isGreyTag() {
        let g = RowGlyph.resolve(kind: "income", categoryIcon: nil, categoryColorHex: nil)
        XCTAssertEqual(g, RowGlyph.Glyph(symbol: "tag.fill", tint: .unset))
    }

    /// An unknown/absent kind must still produce something drawable — a row with no
    /// glyph would leave the text column ragged against its neighbours.
    func test_nilKind_stillResolves() {
        XCTAssertEqual(RowGlyph.resolve(kind: nil, categoryIcon: nil, categoryColorHex: nil).symbol,
                       "tag.fill")
        XCTAssertEqual(RowGlyph.resolve(kind: "wat", categoryIcon: "cart", categoryColorHex: "#111111").tint,
                       .category(hex: "#111111"))
    }
}
