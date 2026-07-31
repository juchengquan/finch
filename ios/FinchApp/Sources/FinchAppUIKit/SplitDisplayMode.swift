#if os(iOS)
import UIKit

/// The UIKit half of `SplitVisibilityMapping`: which `DisplayMode` a stored "sidebar
/// collapsed" preference means, and which display modes are worth storing.
///
/// Same contract as the SwiftUI version, same storage key, so the preference carries
/// across a build that switches shells rather than silently resetting. The arity split
/// exists for the same reason it does there: "collapsed" means a different mode
/// depending on how many columns are on screen.
enum SplitDisplayMode {

    enum Arity { case three, two }

    /// Shared with `PersistedSplitVisibility.storageKey` — deliberately the same
    /// defaults key, so a user who collapsed the sidebar under the SwiftUI shell finds
    /// it still collapsed under this one.
    static let storageKey = "finch.sidebarCollapsed"

    static var storedCollapsed: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    /// The display mode a preference maps to.
    ///
    /// Three columns: collapsed hides the sidebar and leaves list + detail
    /// (`.oneBesideSecondary`), expanded shows all three (`.twoBesideSecondary`) —
    /// mirroring `.doubleColumn` / `.all` in `NavigationSplitViewVisibility`.
    /// Two columns: collapsed is detail only, expanded is sidebar + detail.
    static func preferred(collapsed: Bool, arity: Arity) -> UISplitViewController.DisplayMode {
        switch arity {
        case .three: return collapsed ? .oneBesideSecondary : .twoBesideSecondary
        case .two:   return collapsed ? .secondaryOnly : .oneBesideSecondary
        }
    }

    /// The preference a display mode represents, or nil when it represents nothing
    /// worth recording.
    ///
    /// `.automatic` is the system saying "I haven't decided", and the overlay/displace
    /// modes are transient presentations rather than a layout the user chose — writing
    /// either down would pin the sidebar to a state they never asked for. nil means
    /// "don't record", exactly as the SwiftUI mapping's nil does.
    static func collapsed(from mode: UISplitViewController.DisplayMode, arity: Arity) -> Bool? {
        if mode == .automatic { return nil }
        if mode == preferred(collapsed: true, arity: arity) { return true }
        if mode == preferred(collapsed: false, arity: arity) { return false }
        return nil
    }
}
#endif
