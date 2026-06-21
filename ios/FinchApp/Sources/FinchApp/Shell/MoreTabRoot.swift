import SwiftUI

/// The custom "More" tab root (compact width). A real `NavigationStack` listing
/// the overflow destinations (Settings) so they push with their own titles and a
/// single back button — replacing SwiftUI's system "More" tab. `SettingsTab` uses
/// `MoreTabNavigationStack`, which is a no-op in compact width, so its
/// `.navigationTitle` attaches to this stack.
struct MoreTabRoot: View {
    @Binding var path: [AppTab]

    private static let overflow: [AppTab] = [.settings]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(Self.overflow, id: \.self) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: AppTab.self) { tab in
                // Set the title here on the destination: the screens' own
                // `.navigationTitle` (deep inside `MoreTabNavigationStack`'s
                // conditional content) doesn't surface through
                // `navigationDestination`, so the pushed bar showed no title.
                destination(for: tab)
                    .navigationTitle(tab.title)
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .settings: SettingsTab()
        default:        EmptyView()
        }
    }
}
