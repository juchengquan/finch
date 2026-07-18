import Foundation

/// Delay presenting a row-anchored confirmation until the CONTEXT-MENU
/// dismissal animation has settled — presenting during the zoom-back tears the
/// just-presented popout down immediately. (Swipe actions don't need this: the
/// swipe Delete buttons drop `role: .destructive` instead, whose fake
/// row-removal animation was what killed swipe-triggered popouts; the menu's
/// own dismiss animation masks this delay entirely.)
enum RowPresentation {
    static func afterCollapse(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
