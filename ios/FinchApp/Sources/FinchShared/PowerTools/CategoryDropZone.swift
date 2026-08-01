import CoreGraphics

/// Which drop zone a drop point falls in, relative to the target row.
///
/// Lives in `FinchShared` rather than beside either screen because both the UIKit
/// and the SwiftUI Categories implement the same drag, and they had already drifted
/// once with two copies of these constants. One definition, two callers.
///
/// Extracted as a pure function deliberately: `idb` has no drag command (only
/// press-move-release, which never triggers a UIKit drag lift), so the gesture that
/// reaches `performDropWith` cannot be driven automatically. This is the one part of
/// reorder-by-drag that CAN be tested, so it is — leaving only "does UIKit deliver
/// the drop" for a human. `CategoryReorder` itself is already unit-tested.
enum CategoryDropZone: Equatable {
    /// Insert before the target, within its sibling group.
    case before
    /// Nest under the target.
    case into
    /// Insert after the target.
    case after

    /// `pointY` and `cellMinY` share a coordinate space (the collection view's).
    ///
    /// - Parameter allowsNesting: whether `.into` is on offer at all. Drive it from
    ///   `allowsNesting(dragDX:)` — nesting is meant to be a deliberate act, not
    ///   something vertical position can do to you by accident.
    ///
    /// With nesting available the row is quarters — top inserts before, bottom
    /// inserts after, middle half nests. Without it the row is halves, so wherever
    /// you land you get a position rather than a level change.
    static func at(pointY: CGFloat,
                   cellMinY: CGFloat,
                   cellHeight: CGFloat,
                   allowsNesting: Bool = true) -> CategoryDropZone {
        guard cellHeight > 0 else { return allowsNesting ? .into : .before }
        let fraction = (pointY - cellMinY) / cellHeight
        guard allowsNesting else { return fraction < 0.5 ? .before : .after }
        if fraction < 0.25 { return .before }
        if fraction > 0.75 { return .after }
        return .into
    }

    /// Whether a row can take a dropped category as a child.
    ///
    /// **Only a group you can already see.** The receiver must have at least one
    /// child AND be expanded, so the children it would join are on screen and the
    /// drop lands somewhere visible. A childless category is never a receiver —
    /// which means dragging cannot create a NEW level of nesting; the add-a-
    /// sub-category action does that, where you can see what you are making.
    ///
    /// This applies at every depth, which is the whole point: a sub-category with
    /// children of its own is a receiver on exactly the same terms, and only while
    /// it is open.
    ///
    /// Three earlier rules failed before this one. Nesting first owned the middle
    /// half of EVERY row, so it beat same-level two-to-one on target area. Refusing
    /// it on expanded parents inverted the problem and let folded rows swallow drops
    /// aimed past them. Gating it on a sideways drag worked but asked the user to
    /// learn a gesture, and could not be expressed in SwiftUI at all, which forced
    /// iPhone and iPad apart. This rule needs no gesture and no drag translation —
    /// only facts both screens already have — so they can finally agree.
    static func canReceiveChild(hasChildren: Bool, isExpanded: Bool) -> Bool {
        hasChildren && isExpanded
    }
}
