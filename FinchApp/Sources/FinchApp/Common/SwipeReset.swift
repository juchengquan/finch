import SwiftUI

extension View {
    /// Closes any open swipe-action row when this view leaves the screen and returns, by
    /// rebuilding the view's identity (`.id`) while it is off-screen (so the rebuild is invisible).
    /// Apply to a `List` that has `.swipeActions`.
    ///
    /// SwiftUI exposes no API to close an open swipe; a fresh `.id` is the only mechanism. The
    /// rebuild is memory-flat and happens off-screen, so it is effectively free (verified on-device).
    ///
    /// - Parameter enabled: pass `false` to suppress the rebuild while an in-list selection or edit
    ///   mode is active — a rebuild would drop that selection. Defaults to `true`.
    func resetsSwipeOnNavigation(enabled: Bool = true) -> some View {
        modifier(SwipeResetModifier(enabled: enabled))
    }
}

/// Bumps a private token on `.onDisappear`, changing the wrapped view's `.id` so SwiftUI rebuilds
/// it fresh (swipes closed) the next time it appears.
private struct SwipeResetModifier: ViewModifier {
    let enabled: Bool
    @State private var token = 0
    func body(content: Content) -> some View {
        content
            .id(token)
            .onDisappear { if enabled { token &+= 1 } }
    }
}
