import SwiftUI
import FinchCore

/// Read-only transaction detail for the iPad/macOS third column (#414 CP1).
/// Resolves the transaction live from the store so it reflects edits; the Edit
/// button opens the existing EditTransactionSheet — the sheet stays the single
/// write path (no inline editing). Compact width never shows this view.
struct TransactionDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let txId: String
    @State private var editing: Tx?
    @State private var previewURL: URL?

    private var txn: Tx? { store.txns.first { $0.id == txId } }

    var body: some View {
        if let t = txn {
            List {
                headerSection(t)
                factsSection(t)
                statusSection(t)
                if let splits = t.splits, !splits.isEmpty { splitsSection(splits) }
                if let refunded = t.refundedTransactionId { refundSection(refunded) }
                receiptsSection(t)
            }
            .navigationTitle("Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                }
            }
            .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
            .quickLookPreview($previewURL)
        } else {
            // Deleted / ledger switched under us; the shell also guards.
            DetailPlaceholder(systemImage: "list.bullet", label: "Select a transaction")
        }
    }

    @ViewBuilder private func headerSection(_ t: Tx) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: TxnKindIcon.icon(for: t.kind))
                    .font(.title2)
                    .foregroundStyle(t.amount < 0 ? .red : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.merchant).font(.headline)
                    // t.amount is already ledger-base (t.currency is the tx's NATIVE currency — displayMoney(from:) would double-convert)
                    Text(store.displayMoneyBase(t.amount))
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder private func factsSection(_ t: Tx) -> some View {
        Section {
            LabeledContent("Date", value: t.time.map { "\(t.date) \($0)" } ?? t.date)
            if let cat = t.category {
                LabeledContent("Category", value: store.categoryName(cat) ?? cat)
            }
            if let acct = store.accounts.first(where: { $0.id == t.account }) {
                LabeledContent("Account", value: acct.name ?? t.account)
            }
            if let tags = t.tags, !tags.isEmpty {
                LabeledContent("Tags", value: tags.joined(separator: ", "))
            }
            if let note = t.note, !note.isEmpty {
                LabeledContent("Note", value: note)
            }
        }
    }

    @ViewBuilder private func statusSection(_ t: Tx) -> some View {
        Section {
            LabeledContent("Status", value: (t.pending ?? false) ? "Pending" : "Confirmed")
            if let cleared = t.clearedAt {
                LabeledContent("Cleared", value: String(cleared.prefix(10)))
            }
        }
    }

    @ViewBuilder private func splitsSection(_ splits: [TxSplit]) -> some View {
        Section("Splits") {
            ForEach(Array(splits.enumerated()), id: \.offset) { _, s in
                LabeledContent(store.categoryName(s.categoryId) ?? s.categoryId ?? "—",
                               value: store.displayMoneyBase(s.amountBase))
            }
        }
    }

    @ViewBuilder private func refundSection(_ refundedId: String) -> some View {
        Section {
            if let orig = store.txns.first(where: { $0.id == refundedId }) {
                LabeledContent("Refunds", value: "\(orig.merchant) · \(orig.date)")
            } else {
                LabeledContent("Refunds", value: "transaction \(refundedId)")
            }
        }
    }

    @ViewBuilder private func receiptsSection(_ t: Tx) -> some View {
        let atts = store.attachments(for: t.id)
        if !atts.isEmpty {
            Section("Receipts") {
                ForEach(atts) { att in
                    Button { previewURL = store.attachmentURL(for: att) } label: {
                        Label(att.originalFilename ?? "Receipt (\(att.kind))", systemImage: "paperclip")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
