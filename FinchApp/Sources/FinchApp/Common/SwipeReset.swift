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

// MARK: - Component 2 — scroll preservation for long transaction feeds

/// Pure helpers for feeds that must also keep their scroll position across the reset rebuild.
enum SwipeReset {
    /// The topmost currently-visible row: the first id in `order` (the full display order of row
    /// ids) that is present in `visible` (the set of on-screen row ids). `nil` when nothing known
    /// is visible. Ordering comes from `order`, never from `Set` iteration.
    static func topVisibleID(order: [String], visible: Set<String>) -> String? {
        order.first { visible.contains($0) }
    }

    /// The anchor to keep for a pending scroll-restore. When the reset is gated off
    /// (`enabled == false`) no rebuild happens, so any previously-saved anchor must be dropped —
    /// otherwise the next return would restore a stale position from an earlier navigation.
    static func nextSavedAnchor(enabled: Bool, currentAnchor: String?) -> String? {
        enabled ? currentAnchor : nil
    }
}

extension View {
    /// Feed rows: report on-screen visibility and keep `anchor` pointing at the current top-visible
    /// row. `anchor` is updated on `onAppear` ONLY — never on `onDisappear` — so it survives the
    /// navigate-away teardown (when many rows disappear at once) holding the last on-screen top
    /// instead of being cleared. `order` is the full display order of `Tx.id`s.
    func tracksTopRow(id: String, order: [String],
                      visible: Binding<Set<String>>, anchor: Binding<String?>) -> some View {
        onAppear {
            visible.wrappedValue.insert(id)
            anchor.wrappedValue = SwipeReset.topVisibleID(order: order, visible: visible.wrappedValue)
        }
        .onDisappear { visible.wrappedValue.remove(id) }
    }

    /// Feed `List` (MUST be inside a `ScrollViewReader`): rebuild on navigate-away to close swipes,
    /// then restore the frozen anchor on return. On leave, `anchor` (the live top) is frozen into
    /// `savedAnchor` — which row re-appears on return cannot overwrite — then the token bumps.
    /// On return, `scrollTo(savedAnchor)` runs `async` so the rebuilt list lays out first.
    func resetsSwipeAndRestoresScroll(enabled: Bool, token: Binding<Int>,
                                      anchor: Binding<String?>, savedAnchor: Binding<String?>,
                                      proxy: ScrollViewProxy) -> some View {
        self
            .id(token.wrappedValue)
            .onDisappear {
                // Freeze the live top anchor for restore-on-return; a gated navigation drops it
                // (no rebuild happens, so there is nothing to restore).
                savedAnchor.wrappedValue = SwipeReset.nextSavedAnchor(enabled: enabled, currentAnchor: anchor.wrappedValue)
                if enabled { token.wrappedValue &+= 1 }
            }
            .onAppear {
                if let a = savedAnchor.wrappedValue {
                    DispatchQueue.main.async {
                        proxy.scrollTo(a, anchor: .top)
                        savedAnchor.wrappedValue = nil   // one-shot: consume so a later gated return can't restore stale
                    }
                }
            }
    }
}
