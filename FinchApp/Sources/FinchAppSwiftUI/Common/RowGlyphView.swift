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
    /// What VoiceOver reads for the glyph, or **nil for decorative** — which is the
    /// default, and right wherever the row's own text already names what the glyph
    /// depicts.
    ///
    /// Without this an SF Symbol announces its OWN name, so a category row read
    /// "Shopping Cart, Groceries, 7 transactions" — the glyph as a separate stop
    /// before the word it duplicates. The transaction rows are the exception: they
    /// pass the KIND here, because the stripe that used to carry it now draws at the
    /// trailing edge and a combined row label follows layout order.
    var a11yLabel: Text? = nil

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(tint)
            // A fixed box, so names line up down the column whatever glyph each row
            // draws — symbols differ in width and a hugging frame makes the text
            // column ragged.
            .frame(width: size + 4)
            .accessibilityLabel(a11yLabel ?? Text(verbatim: ""))
            .accessibilityHidden(a11yLabel == nil)
    }
}
