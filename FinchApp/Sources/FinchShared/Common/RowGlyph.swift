import Foundation

/// Which glyph a transaction-shaped row draws at its LEADING edge, and what tints it.
///
/// The leading edge used to carry a thin kind stripe, described in its own comment as
/// "the leading icon's replacement". The stripe has moved to the trailing edge (beside
/// the amount), which frees that space for the icon it stood in for — so this decides
/// what goes there.
///
/// Pure, and shared by `TxRow` and `ScheduledRow` so the two lists cannot drift: they
/// were deliberately matched before, and the stripe's twin in `ScheduledRow` says so.
/// The view maps `Tint` to a real colour; keeping that out of here is what lets the
/// choice be unit-tested without a store or a rendered view.
enum RowGlyph {

    /// What colours the glyph. Deliberately not a `Color` — see the type's note.
    enum Tint: Equatable {
        /// The category's effective colour (its own, or the nearest ancestor's).
        case category(hex: String)
        /// The row's own kind colour — transfers and adjustments ARE their kind.
        case kind
        /// No category set: grey, matching the existing grey "Uncategorized" title so
        /// the row reads as *unset* rather than as some category that happens to be grey.
        case unset
    }

    struct Glyph: Equatable {
        let symbol: String
        let tint: Tint
    }

    /// - Parameters:
    ///   - kind: the transaction kind (`expense`, `income`, `transfer`, …). `ScheduledRow`
    ///     passes its template `type`, which uses the same vocabulary.
    ///   - categoryIcon: the category's effective icon NAME (not an SF Symbol), or nil
    ///     when the category exists but neither it nor any ancestor sets one.
    ///   - categoryColorHex: the category's effective colour, or **nil when the row has
    ///     no category at all**. `effectiveColor` always resolves for a real category
    ///     (it falls back to the palette default), so nil here means exactly "no
    ///     category" — which is why it, not `categoryIcon`, is the presence test.
    static func resolve(kind: String?, categoryIcon: String?, categoryColorHex: String?) -> Glyph {
        // Kind FIRST: a transfer moves money between the user's own accounts and an
        // adjustment is booked by the engine. Those are category-less by nature, not by
        // neglect, so they get a glyph that says what they are — and they keep it even
        // on the rare row that does carry a category, so a transfer always reads as one.
        switch kind {
        case "transfer":   return Glyph(symbol: "arrow.left.arrow.right", tint: .kind)
        case "adjustment": return Glyph(symbol: "slider.horizontal.3", tint: .kind)
        default: break
        }
        if let hex = categoryColorHex {
            // A category with no icon anywhere up its chain still resolves, because
            // `CategoryIcon.symbol(for:)` falls back to "tag.fill".
            return Glyph(symbol: CategoryIcon.symbol(for: categoryIcon), tint: .category(hex: hex))
        }
        return Glyph(symbol: "tag.fill", tint: .unset)
    }
}
