import SwiftUI
import FinchCore

/// Split a transaction across ≥2 category legs. Amounts are magnitudes that must
/// sum to the total; the engine applies the sign. Transaction-agnostic: Edit drives
/// it with `.existing(id:)` (applies `setTransactionSplits`); Add drives it with
/// `.draft(onSave:)` (returns the splits to the caller). `store` is read only in
/// `body`, never `init`.
struct SplitEditorView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    typealias DraftSplit = (categoryId: String?, amount: Double)
    enum Target {
        case existing(id: String)
        case draft(onSave: ([DraftSplit]) -> Void)
    }

    private let target: Target
    private let total: Double
    private let isIncome: Bool
    private let currencyOverride: String?       // nil → fall back to store.baseCurrency
    private let editingExistingSplit: Bool      // controls "Remove split" visibility

    private struct Row: Identifiable { let id = UUID(); var categoryId: String; var amount: String }
    @State private var rows: [Row]
    @State private var errorMessage: String?

    private var displayCurrency: String { currencyOverride ?? store.baseCurrency }
    private var allocated: Double { rows.reduce(0) { $0 + (DecimalInput.parse($1.amount) ?? 0) } }
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { isIncome ? $0.kind == "income" : $0.kind != "income" }
    }

    /// Designated initializer (used by Add for draft mode).
    init(total: Double, isIncome: Bool, currency: String?,
         initialSplits: [DraftSplit]?, target: Target, editingExistingSplit: Bool = false) {
        self.total = total
        self.isIncome = isIncome
        self.currencyOverride = currency
        self.target = target
        self.editingExistingSplit = editingExistingSplit
        if let s = initialSplits, s.count >= 2 {
            _rows = State(initialValue: s.map { Row(categoryId: $0.categoryId ?? "", amount: String(format: "%g", abs($0.amount))) })
        } else if let first = initialSplits?.first {
            // Seed row 1 from the single source category + total; row 2 empty.
            _rows = State(initialValue: [
                Row(categoryId: first.categoryId ?? "", amount: String(format: "%g", abs(first.amount))),
                Row(categoryId: "", amount: ""),
            ])
        } else {
            _rows = State(initialValue: [Row(categoryId: "", amount: ""), Row(categoryId: "", amount: "")])
        }
    }

    /// Convenience for the Edit flow — unchanged call site `SplitEditorView(txn:)`.
    init(txn: Tx) {
        let alreadySplit = (txn.splits?.count ?? 0) >= 2
        let initial: [DraftSplit]? = alreadySplit
            ? txn.splits!.map { (categoryId: $0.categoryId, amount: abs($0.amount)) }
            : [(categoryId: txn.category, amount: abs(txn.nativeAmount ?? txn.amount))]
        self.init(total: abs(txn.nativeAmount ?? txn.amount),
                  isIncome: txn.amount > 0,
                  currency: txn.currency,
                  initialSplits: initial,
                  target: .existing(id: txn.id),
                  editingExistingSplit: alreadySplit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Transaction total", value: store.displayNative(total, currency: displayCurrency))
                    LabeledContent("Allocated", value: store.displayNative(allocated, currency: displayCurrency))
                        .foregroundStyle(abs(allocated - total) <= 0.01 ? .primary : .secondary)
                }
                Section("Splits") {
                    ForEach($rows) { $row in
                        HStack {
                            Picker("", selection: $row.categoryId) {
                                Text("Uncategorized").tag("")
                                ForEach(categories) { Text($0.name).tag($0.id) }
                            }.labelsHidden()
                            Spacer()
                            TextField("0.00", text: $row.amount)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    Button("Add split") { rows.append(Row(categoryId: "", amount: "")) }
                }
                if editingExistingSplit, case .existing = target {
                    Section {
                        Button("Remove split (single category)", role: .destructive) { removeSplit() }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Split")
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
        let parsed: [DraftSplit] = rows.compactMap { r in
            guard let a = DecimalInput.parse(r.amount), a > 0 else { return nil }
            return (categoryId: r.categoryId.isEmpty ? nil : r.categoryId, amount: a)
        }
        guard parsed.count >= 2 else { errorMessage = "Add at least two splits with amounts."; return }
        let sum = parsed.reduce(0) { $0 + $1.amount }
        guard abs(sum - total) <= 0.01 * Double(parsed.count) else {
            errorMessage = "Splits must add up to \(Money.format(total, currency: displayCurrency))."
            return
        }
        switch target {
        case .draft(let onSave):
            onSave(parsed)
            dismiss()
        case .existing(let id):
            let payload: [JSONValue] = parsed.map { .object([
                "categoryId": $0.categoryId.map(JSONValue.string) ?? .null, "amount": .double($0.amount)]) }
            do { try store.apply(.setTransactionSplits, Args(["id": .string(id), "splits": .array(payload)])); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }

    private func removeSplit() {
        guard case .existing(let id) = target else { return }
        do { try store.apply(.setTransactionSplits, Args(["id": .string(id), "splits": .array([])])); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}
