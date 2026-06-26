import SwiftUI
import FinchCore

/// The Ledger screen — a master→detail flow: a list of every ledger
/// (LedgerListView), drilling into a per-ledger detail (LedgerDetailView). On
/// iPhone it's pushed from the top-left corner control (`ledgerPush()`); on
/// iPad/Mac it's a sidebar section. The single global active ledger scopes the
/// rest of the app.
struct LedgerTab: View {
    var body: some View {
        NavigationStack {
            LedgerListView().navigationTitle("Ledger")
        }
    }
}
