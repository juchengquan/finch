import SwiftUI
import FinchCore

/// A chosen (initiating A, picked B) pair for a merge; the alert decides which survives.
private struct MerchantMergePair: Identifiable {
    let a: Counterparty
    let b: Counterparty
    var id: String { a.id + "|" + b.id }
}

/// Merchants admin — a flat, name-only list (Settings top-level). Mirrors the
/// Categories/Tags pages: search, a transaction-count pill, tap → the merchant's
/// transactions, swipe Rename/Delete/Merge, + to add. Plus verify/unverify
/// (merchant-only) and merge (single + multi-select). All via FinchStore.apply.
struct MerchantsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var selectedMerchantId: String?
    @State private var showingAdd = false
    @State private var editing: Counterparty?
    @State private var pendingDelete: Counterparty?
    @State private var search = ""
    @State private var errorMessage: String?
    // merge state (mirrors CategoriesView)
    @State private var mergingFrom: Counterparty?
    @State private var pendingMerge: MerchantMergePair?
    @State private var mergeChoice: MerchantMergePair?
    @State private var isSelecting = false
    @State private var selected: Set<String> = []
    @State private var mergeManySurvivorChoice: [Counterparty]?

    private var filtered: [Counterparty] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? store.merchants : store.merchants.filter { $0.name.lowercased().contains(q) }
    }
    private var byId: [String: Counterparty] { Dictionary(uniqueKeysWithValues: store.merchants.map { ($0.id, $0) }) }

    var body: some View {
        let counts = Selectors.counterpartyTxCounts(store.txns, store.merchants, store.activeLedgerId)
        return Group {
            if store.merchants.isEmpty {
                ContentUnavailableView("No merchants", systemImage: "storefront",
                                       description: Text("Merchants appear as you add transactions, or add one with +."))
            } else {
                List { ForEach(filtered) { cp in row(cp, counts) } }
                    .modifier(SearchableModifier(text: $search))
            }
        }
        .navigationTitle("Merchants")
        .errorAlert($errorMessage)
        .toolbar { toolbarContent }
        .navigationDestination(item: $selectedMerchantId) { id in
            if let cp = store.merchants.first(where: { $0.id == id }) { CounterpartyDetailView(counterparty: cp) }
        }
        .sheet(isPresented: $showingAdd) { CounterpartyNameSheet(counterparty: nil) }
        .sheet(item: $editing) { CounterpartyNameSheet(counterparty: $0) }
        // Single-merge target picker; present keep-name alert only after it dismisses.
        .sheet(item: $mergingFrom, onDismiss: {
            if let p = pendingMerge { mergeChoice = p; pendingMerge = nil }
        }) { a in mergeTargetSheet(a) }
        .alert("Keep which name?", isPresented: Binding(
            get: { mergeChoice != nil }, set: { if !$0 { mergeChoice = nil } }),
            presenting: mergeChoice) { pair in
            Button("Keep \"\(pair.a.name)\"") { merge(source: pair.b, target: pair.a) }
            Button("Keep \"\(pair.b.name)\"") { merge(source: pair.a, target: pair.b) }
            Button("Cancel", role: .cancel) {}
        } message: { pair in
            if let msg = mergeImpactMessage(txCount: mergeTxCount(pair.a, pair.b)) { Text(msg) }
        }
        .alert("Keep which name?", isPresented: Binding(
            get: { mergeManySurvivorChoice != nil }, set: { if !$0 { mergeManySurvivorChoice = nil } }),
            presenting: mergeManySurvivorChoice) { picks in
            ForEach(picks) { survivor in
                Button("Keep \"\(survivor.name)\"") { mergeMany(keeping: survivor, from: picks) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { picks in
            if let msg = mergeImpactMessage(txCount: mergeManyTxCount(picks)) { Text(msg) }
        }
        .alert("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { cp in
            Button("Delete", role: .destructive) { delete(cp) }
            Button("Cancel", role: .cancel) {}
        } message: { cp in
            let n = counts[cp.id] ?? 0
            if n > 0 { Text("\(cp.name) — \(n) transactions keep the name but lose the merchant link.") }
            else { Text("This permanently deletes \(cp.name).") }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge (\(selected.count))") {
                    mergeManySurvivorChoice = selected.compactMap { byId[$0] }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }.disabled(selected.count < 2)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { isSelecting = false; selected = [] } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Merchant")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isSelecting = true; selected = [] } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More")
            }
        }
    }

    @ViewBuilder private func row(_ cp: Counterparty, _ counts: [String: Int]) -> some View {
        if isSelecting {
            Button {
                if selected.contains(cp.id) { selected.remove(cp.id) } else { selected.insert(cp.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected.contains(cp.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected.contains(cp.id) ? Color.accentColor : .secondary)
                    rowLabel(cp, counts)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button { selectedMerchantId = cp.id } label: { rowLabel(cp, counts) }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    // Rename first ⇒ outer edge / full-swipe default (never delete).
                    Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }.tint(.accentColor)
                    Button { pendingDelete = cp } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                    Button { mergingFrom = cp } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }.tint(.orange)
                }
                .contextMenu {
                    Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }
                    Button { toggleVerify(cp) } label: { Label(cp.isVerified ? "Unverify" : "Verify", systemImage: "checkmark.seal") }
                    Button { mergingFrom = cp } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                    Button(role: .destructive) { pendingDelete = cp } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    @ViewBuilder private func rowLabel(_ cp: Counterparty, _ counts: [String: Int]) -> some View {
        HStack(spacing: 8) {
            MerchantLabel(name: cp.name, isVerified: cp.isVerified)
            Spacer(minLength: 8)
            CountPill(count: counts[cp.id] ?? 0)
        }
        .contentShape(Rectangle())
    }

    private func mergeTargetSheet(_ a: Counterparty) -> some View {
        NavigationStack {
            List {
                let targets = store.merchants.filter { $0.id != a.id }
                if targets.isEmpty {
                    ContentUnavailableView("No other merchants", systemImage: "arrow.triangle.merge",
                                           description: Text("There's nothing to merge \(a.name) with yet."))
                } else {
                    ForEach(targets) { t in
                        Button {
                            pendingMerge = MerchantMergePair(a: a, b: t)
                            mergingFrom = nil
                        } label: { MerchantLabel(name: t.name, isVerified: t.isVerified).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Merge \(a.name) with…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { mergingFrom = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
            }
        }
    }

    // MARK: actions
    private func toggleVerify(_ cp: Counterparty) {
        do { try store.apply(cp.isVerified ? .unverifyCounterparty : .verifyCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ cp: Counterparty) {
        errorMessage = nil
        do { try store.apply(.deleteCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func merge(source: Counterparty, target: Counterparty) {
        errorMessage = nil; mergeChoice = nil
        do { try store.apply(.mergeCounterparty, Args(["sourceId": .string(source.id), "targetId": .string(target.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func mergeMany(keeping survivor: Counterparty, from all: [Counterparty]) {
        errorMessage = nil; mergeManySurvivorChoice = nil
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        do {
            try store.apply(.mergeCounterparties, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false; selected = []
        } catch { errorMessage = i18nMessage(error) }
    }
    /// Choice-independent union of transactions referencing either merchant.
    private func mergeTxCount(_ a: Counterparty, _ b: Counterparty) -> Int {
        let ledger = store.activeLedgerId
        let ids = Set(Selectors.merchantTransactions(store.txns, store.merchants, a.id, ledger, includePending: true).map(\.id))
            .union(Selectors.merchantTransactions(store.txns, store.merchants, b.id, ledger, includePending: true).map(\.id))
        return ids.count
    }
    private func mergeManyTxCount(_ cps: [Counterparty]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for c in cps { ids.formUnion(Selectors.merchantTransactions(store.txns, store.merchants, c.id, ledger, includePending: true).map(\.id)) }
        return ids.count
    }
}

/// Add or rename a counterparty (name only).
struct CounterpartyNameSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let counterparty: Counterparty?
    @State private var name: String
    @State private var errorMessage: String?

    init(counterparty: Counterparty?) {
        self.counterparty = counterparty
        _name = State(initialValue: counterparty?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(counterparty == nil ? "Add Merchant" : "Rename Merchant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let counterparty {
                try store.apply(.updateCounterparty, Args(["id": .string(counterparty.id), "patch": .object(["name": .string(trimmed)])]))
            } else {
                try store.apply(.createCounterparty, Args(["name": .string(trimmed)]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
