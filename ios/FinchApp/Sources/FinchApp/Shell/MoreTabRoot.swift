import SwiftUI

/// The custom "More" tab root (compact width). A real `NavigationStack` listing
/// the overflow destinations (Scheduled, Settings) so they push with their own
/// titles and a single back button — replacing SwiftUI's system "More" tab.
/// `ScheduledTab`/`SettingsTab` use `MoreTabNavigationStack`, which is a no-op in
/// compact width, so their `.navigationTitle` attaches to this stack.
struct MoreTabRoot: View {
    @Binding var path: [AppTab]

    private static let overflow: [AppTab] = [.scheduled, .settings]

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
                destination(for: tab)
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .scheduled: ScheduledTab()
        case .settings:  SettingsTab()
        default:         EmptyView()
        }
    }
}
