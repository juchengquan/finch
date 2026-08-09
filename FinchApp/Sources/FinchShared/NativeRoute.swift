import SwiftUI

/// The seam between the SwiftUI screens and the UIKit shell during the migration.
///
/// A SwiftUI screen that wants to drill in asks the environment to handle the
/// route natively. The UIKit shell installs a handler that pushes the converted
/// view controller and returns `true`; anywhere without one — macOS, the iPad
/// split shell, previews — the default returns `false` and the screen falls back
/// to the navigation it already had.
///
/// That fallback is what makes the migration incremental: a route becomes native
/// the moment its screen is converted and the shell claims it, with no change to
/// the calling site beyond asking first.
public enum NativeRoute: Equatable {
    case activity
    case account(String)
    case budget(String)
    case categories
    case tags
    case merchants
    case currencies
    case powerTools
    case appearance
    case notifications
    case security
    case backupsSync
    case about
}

public struct NativeRouteKey: EnvironmentKey {
    /// Not handled — the caller keeps its existing SwiftUI navigation.
    public static let defaultValue: (NativeRoute) -> Bool = { _ in false }
}

public extension EnvironmentValues {
    var nativeRoute: (NativeRoute) -> Bool {
        get { self[NativeRouteKey.self] }
        set { self[NativeRouteKey.self] = newValue }
    }
}
