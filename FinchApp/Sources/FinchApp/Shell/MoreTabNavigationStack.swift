import SwiftUI

/// A `NavigationStack` that steps aside for the system **"More" tab**.
///
/// On iPhone the `TabView` has 6 tabs (`AppTab.allCases`); iOS auto-collapses
/// everything past the 4th into a system "More" tab, which is its own UIKit
/// navigation controller. The two overflow screens (Scheduled, Settings) used to
/// wrap their bodies in their own `NavigationStack`, so they rendered a second
/// nav bar *inside* the More tab's nav controller — a doubled nav bar with a
/// stray "‹ More" back button on top of the screen's own back button.
///
/// In **compact** width these screens are always inside More, so we rely on the
/// system-provided navigation controller (destination-based `NavigationLink`s and
/// `.navigationTitle` attach to it correctly). In **regular** width (iPad/Mac
/// split view) there is no More tab and the detail column needs a real stack, so
/// we supply one.
///
/// Use this only for tab roots that can land in the More overflow. The four
/// primary tabs are never in More and keep their own `NavigationStack`.
struct MoreTabNavigationStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder var content: () -> Content

    var body: some View {
        if sizeClass == .compact {
            content()
        } else {
            NavigationStack { content() }
        }
    }
}
