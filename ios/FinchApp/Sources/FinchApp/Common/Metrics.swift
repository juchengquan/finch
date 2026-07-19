import CoreGraphics

/// App-wide layout metric tokens — tune here to adjust globally.
/// (Named `Metrics`, not `Layout`, to avoid colliding with SwiftUI's `Layout` protocol.)
enum Metrics {
    /// Gap between grouped `List` sections — the spacing between the sectionized
    /// blocks (e.g. the account groups on the Accounts page). Set once at
    /// `AdaptiveShell` via `.listSectionSpacing(...)`; because that's an
    /// environment value, every descendant `List` across all tabs inherits it.
    /// Individual screens may still override it locally (e.g. the Add sheet's 6).
    static let sectionSpacing: CGFloat = 12
}
