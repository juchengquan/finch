import SwiftUI
import FinchCore

/// Picks the original expense a refund offsets. Lists recent expenses in the active
/// ledger (newest first), searchable by merchant. `onPick(nil)` clears the link.
struct RefundSourcePickerView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (String?) -> Void
    @State private var query = ""

    private var expenses: [Tx] {
        store.txns
            .filter { $0.ledgerId == store.activeLedgerId && ($0.kind == "expense" || $0.amount < 0) }
            .filter { query.isEmpty || $0.merchant.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.date, $0.time ?? "") > ($1.date, $1.time ?? "") }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("None (no link)") { onPick(nil); dismiss() }
                ForEach(expenses) { tx in
                    Button {
                        onPick(tx.id); dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.merchant.isEmpty ? "—" : tx.merchant).foregroundStyle(.primary)
                                Text(tx.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            // tx.amount is already ledger-base (tx.currency is the tx's
                            // NATIVE currency — displayMoney(from:) double-converts FX).
                            Text(store.displayMoneyBase(tx.amount))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Refunded transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") } }
        }
    }
}
