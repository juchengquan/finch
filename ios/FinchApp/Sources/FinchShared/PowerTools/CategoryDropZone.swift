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

    /// How far right you must drag before a drop nests instead of reordering.
    ///
    /// Same level is the DEFAULT, at every row, expanded or folded — dragging
    /// straight up and down can only ever change position. Nesting is a separate,
    /// deliberate gesture: carry the row sideways and it indents, which is the
    /// Reminders/Notes idiom.
    ///
    /// This replaced two earlier attempts that both tried to infer intent from
    /// vertical position and got it wrong. Nesting first owned the middle HALF of
    /// every row, so it beat same-level two-to-one on target area; narrowing it to
    /// rows whose children were hidden still left folded categories swallowing
    /// drops aimed past them. Position cannot express "I meant to go inside" — only
    /// a second axis can.
    ///
    /// 32pt is comfortably past an idle thumb's horizontal wander during a vertical
    /// drag, and a little over two of the tree's 14pt indent steps, so it reads as
    /// intentional without being a reach.
    static let nestingDragThreshold: CGFloat = 32

    /// Whether a drag that has travelled `dragDX` horizontally may nest.
    /// Rightward only — dragging LEFT is not an un-nest gesture here; the
    /// "Top level" drop row does that job.
    static func allowsNesting(dragDX: CGFloat) -> Bool { dragDX >= nestingDragThreshold }
}
