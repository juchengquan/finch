import SwiftUI
import FinchCore

/// A category's transactions + aggregate stats. Pushed from the Categories page
/// when a row is tapped. Mirrors `CounterpartyDetailView` (the merchants analog):
/// membership matches the row's count badge (`categoryTransactions` ≙
/// `categoryTxCounts`, i.e. includes split legs, excludes pending).
struct CategoryDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let category: CategoryRow
    @State private var editing: Tx?
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled
    @State private var pendingDelete: Tx?   // delete awaiting confirmation
    @State private var errorMessage: String?

    /// One row per PURCHASE, not per payment. This screen answers "what did I
    /// spend on this" — a purchase paid on two cards is one shop, not two half
    /// shops, and which card paid is not the question being asked here. An
    /// account's own screen is the opposite and deliberately does NOT collapse.
    /// Collapsing here also keeps the count, total and average agreeing with the
    /// list they sit above.
    ///
    /// Amounts are this CATEGORY's share, not the whole purchase — a 100 shop
    /// split 70/30 belongs here as 70, or this screen and the household one
    /// together claim 200 of spend. See `Selectors.categoryShares`.
    private var txns: [Tx] {
        Selectors.categoryPurchases(store.txns, category.id, store.activeLedgerId)
    }
    private var total: Double { txns.reduce(0) { $0 + $1.amount } }
    /// Pending items are excluded from `txns` (and so from the summary + the count
    /// pill on the parent page). Queried separately so they can be surfaced on top
    /// rather than silently omitted — the same "To confirm" treatment
    /// AccountDetailView gives them.
    private var pendingTxns: [Tx] {
        Selectors.byPurchase(
            Selectors.categoryShares(store.txns, category.id, store.activeLedgerId, includePending: true)
                .filter { Selectors.isPendingNow($0, today: store.wallToday) })
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Transactions", value: "\(txns.count)")
                LabeledContent("Total", value: store.displayMoneyBase(total))
                if !txns.isEmpty {
                    LabeledContent("Average", value: store.displayMoneyBase(total / Double(txns.count)))
                }
            }
            if !pendingTxns.isEmpty {
                Section("To confirm (\(pendingTxns.count))") {
                    ForEach(pendingTxns) { row($0) }
                }
            }
            if !txns.isEmpty {
                Section("Transactions") {
                    ForEach(txns) { row($0) }
                }
            }
        }
        .navigationTitle(category.name)
        .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
        .sheet(item: $duplicating) { AddTransactionSheet(prefill: $0) }
        // Window-level ALERT, not a row-anchored confirmationDialog — see
        // ActivityTab (row recycling tears the popout down).
        .alert("Delete transaction?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { tx in
            Button("Delete", role: .destructive) { delete(tx) }
            Button("Cancel", role: .cancel) {}
        } message: { tx in
            // Same multi-leg warning as ActivityTab's delete alert: a split
            // purchase (or a transfer) renders as one row per account leg,
            // and deleting any one row deletes the whole entry.
            if tx.transferGroupId != nil {
                Text("\(tx.merchant) · \(store.displayMoneyBase(tx.amount))") + Text(" " + ActivityFeedView.transferDeleteHint)
            } else if (tx.accountLegCount ?? 1) > 1 {
                Text("\(tx.merchant) · \(store.displayMoneyBase(tx.amount))") + Text(" " + ActivityFeedView.multiLegDeleteHint)
            } else {
                Text("\(tx.merchant) · \(store.displayMoneyBase(tx.amount))")
            }
        }
        .errorAlert($errorMessage)
    }

    private func toggleStatus(_ tx: Tx) {
        // No animation when the row moves. Confirming lifts it out of the
        // "To confirm" section and into its month, and a SwiftUI List animates
        // that by default — the UIKit screens do not, because their snapshots
        // already apply with `animatingDifferences: false`.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            do { try txnToggleStatus(tx, store: store) }
            catch { errorMessage = i18nMessage(error) }
        }
    }
    private func delete(_ tx: Tx) {
        do { try store.deleteTransaction(tx.id); Haptics.warning() }   // also unlinks receipts
        catch { errorMessage = i18nMessage(error) }
    }

    /// The real transaction behind a row.
    ///
    /// Rows here carry only this category's share of their purchase, so every
    /// ACTION has to be handed the whole thing back: an editor opened on a share
    /// would save a fraction of the purchase, and a delete warning quoting one
    /// would understate what it is about to remove. `id` survives the narrowing
    /// precisely so this lookup works.
    private func actual(_ t: Tx) -> Tx { store.txns.first { $0.id == t.id } ?? t }

    @ViewBuilder private func row(_ tx: Tx) -> some View {
        Button { editing = actual(tx) } label: { TxRow(txn: tx, onToggleStatus: { toggleStatus(actual($0)) }, showRunningBalance: false)
                .contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))   // denser rows
            .txnSwipeActions(tx,
                             duplicate: { duplicating = actual($0) },
                             requestDelete: { pendingDelete = actual($0) },
                             toggleStatus: { toggleStatus(actual($0)) },
                             edit: { editing = actual($0) })
    }
}
