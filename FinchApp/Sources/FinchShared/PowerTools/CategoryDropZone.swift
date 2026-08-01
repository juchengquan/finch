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
    /// - Parameter allowsNesting: whether `.into` is on offer at all. **Pass `false`
    ///   when the target's children are already on screen.** An expanded parent needs
    ///   no nest zone: every position inside it is directly reachable by dropping
    ///   between the children you can see, so a nest zone there would only be a
    ///   second, vaguer way to do the same thing — and it would steal half the row
    ///   from the precise one. Collapsed parents and leaves are the opposite case:
    ///   you cannot drop "among" children that aren't rendered, so nesting is the
    ///   only way in, and it gets the middle half.
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
}
