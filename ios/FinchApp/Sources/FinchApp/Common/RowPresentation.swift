import Foundation

/// Sequencing helper for row-anchored confirmation popouts (iOS 26 anchors
/// them at the row). Two uses, both masked by an in-flight animation:
/// 1. Present AFTER a context menu's zoom-back settles — presenting during it
///    tears the popout down immediately. (Swipe actions don't need this: their
///    Delete buttons drop `role: .destructive` instead, whose fake row-removal
///    animation was what killed swipe-triggered popouts.)
/// 2. Delete AFTER the popout's own dismissal settles — mutating the store
///    while the popout is dismissing keeps the source row's cell alive, so the
///    deleted row lingers on screen.
enum RowPresentation {
    static func afterCollapse(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
