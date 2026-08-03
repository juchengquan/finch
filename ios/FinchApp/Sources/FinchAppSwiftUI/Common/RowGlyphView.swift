import SwiftUI

/// A row's leading glyph: an SF Symbol tinted by its subject's colour.
///
/// ONE definition, used by the transaction rows (`TxRow`, `ScheduledRow` — via
/// `RowGlyph`) and by every category list (`CategoriesVC`, `CategoriesView`, the
/// merge-target picker, `CategoryPickerRow`). Those five sites each had their own
/// copy of a swatch before, at three different sizes, which is how they drifted —
/// the same way the calendar's month window drifted when it was re-derived per
/// caller.
///
/// It replaces a filled colour disc with a white glyph on top. The disc read as a
/// swatch, which is right on a screen where you are picking a colour and wrong on a
/// dense list you scan: it put a saturated blob on every row and made the glyph —
/// the part that says WHICH category — small and low-contrast. Colour still carries
/// the identity, it just tints the shape instead of sitting behind it.
///
/// The palette chips in the category editor are deliberately NOT this: those are
/// colour chips, not rows, and a chip has to show the colour as an area to be
/// judged against its neighbours.
struct RowGlyphView: View {
    let symbol: String
    let tint: Color
    /// Point size of the symbol. The default matches the transaction rows; the
    /// category lists pass the same, so the two read as one system.
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(tint)
            // A fixed box, so names line up down the column whatever glyph each row
            // draws — symbols differ in width and a hugging frame makes the text
            // column ragged.
            .frame(width: size + 4)
    }
}
