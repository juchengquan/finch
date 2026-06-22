import SwiftUI
import FinchCore

/// The Ledger tab (home, slot #1) — a compact ledger-context header (active
/// ledger + switcher, net worth, manage) atop the full activity feed for the
/// active ledger. Reuses `ActivityFeedView` with a header section, since a
/// ledger *is* the container for its transactions.
struct LedgerTab: View {
    var body: some View {
        NavigationStack {
            ActivityFeedView(navTitle: "Ledger", headerSection: AnyView(LedgerHeaderSection()))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }
                }
        }
    }
}

/// Ledger-context summary at the top of the Ledger tab: active ledger name with
/// a switcher menu, net worth, and a Manage-ledgers drill-in.
private struct LedgerHeaderSection: View {
    @EnvironmentObject private var store: FinchStore
    private var activeName: String { store.ledgers.first { $0.id == store.activeLedgerId }?.name ?? "Ledger" }

    var body: some View {
        Section {
            HStack {
                Menu {
                    ForEach(store.ledgers) { l in
                        Button {
                            if l.id != store.activeLedgerId { store.activeLedgerId = l.id }
                        } label: {
                            if l.id == store.activeLedgerId { Label(l.name, systemImage: "checkmark") }
                            else { Text(l.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeName).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                    Text(store.netWorthDisplay).font(.headline)
                }
            }
            NavigationLink {
                LedgerManagementView()
            } label: {
                Label("Manage ledgers", systemImage: "books.vertical")
            }
        }
    }
}
