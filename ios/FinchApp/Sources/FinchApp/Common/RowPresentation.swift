import Foundation

/// Delay presenting a row-anchored confirmation until the swipe-actions /
/// context-menu dismissal animation has settled. Presenting DURING the
/// collapse tears the just-presented popout down immediately — the row's cell
/// re-lays out mid-animation and takes its anchored presentation with it.
enum RowPresentation {
    static func afterCollapse(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
