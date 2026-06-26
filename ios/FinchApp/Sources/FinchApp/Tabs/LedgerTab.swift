import SwiftUI
import FinchCore

/// The Ledger tab (home, slot #1) — a master→detail flow: a list of every ledger
/// (LedgerListView), drilling into a per-ledger detail (LedgerDetailView). Ledger
/// selection (Make active) and editing live on those surfaces; the single global
/// active ledger still scopes the rest of the app.
struct LedgerTab: View {
    var body: some View {
        NavigationStack {
            LedgerListView()
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }   // iOS-only; gear is compact-only
                    #endif
                }
                .settingsPush()
        }
    }
}
