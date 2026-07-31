import SwiftUI
import FinchCore

/// Pick another ledger (excludes the active one). Used by "Import from…" and
/// "Copy to…". Calls `onPick(ledgerId)` then dismisses.
struct LedgerPickerSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                let others = store.ledgers.filter { $0.id != store.activeLedgerId }
                if others.isEmpty {
                    ContentUnavailableView("No other ledgers", systemImage: "books.vertical",
                                           description: Text("Create another ledger first."))
                } else {
                    ForEach(others) { l in
                        Button { onPick(l.id); dismiss() } label: {
                            HStack { Text(l.name).foregroundStyle(.primary); Spacer(); Text(l.base).font(.caption).foregroundStyle(.secondary) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") } }
        }
    }
}
