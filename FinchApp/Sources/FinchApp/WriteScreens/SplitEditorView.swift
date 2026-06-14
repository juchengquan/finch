import SwiftUI
import FinchCore

/// Split a transaction across ≥2 category legs (`setTransactionSplits`). Amounts
/// are magnitudes that must sum to the transaction total; the engine applies the
/// transaction's sign. "Remove split" reverts to a single (uncategorized) leg.
struct SplitEditorView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let txn: Tx

    private struct Row: Identifiable { let id = UUID(); var categoryId: String; var amount: String }
    @State private var rows: [Row]
    @State private var errorMessage: String?

    private var total: Double { abs(txn.nativeAmount ?? txn.amount) }
    private var allocated: Double { rows.reduce(0) { $0 + (DecimalInput.parse($1.amount) ?? 0) } }
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { txn.amount > 0 ? $0.kind == "income" : $0.kind != "income" }
    }
    private var isSplit: Bool { (txn.splits?.count ?? 0) >= 2 }

    init(txn: Tx) {
        self.txn = txn
        if let s = txn.splits, s.count >= 2 {
            _rows = State(initialValue: s.map { Row(categoryId: $0.categoryId ?? "", amount: String(format: "%g", abs($0.amount))) })
        } else {
            _rows = State(initialValue: [
                Row(categoryId: txn.category ?? "", amount: String(format: "%g", abs(txn.nativeAmount ?? txn.amount))),
                Row(categoryId: "", amount: ""),
            ])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Transaction total", value: Money.format(total, currency: txn.currency ?? store.baseCurrency))
                    LabeledContent("Allocated", value: Money.format(allocated, currency: txn.currency ?? store.baseCurrency))
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
                if isSplit {
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let parsed = rows.compactMap { r -> (String, Double)? in
            guard let a = DecimalInput.parse(r.amount), a > 0 else { return nil }
            return (r.categoryId, a)
        }
        guard parsed.count >= 2 else { errorMessage = "Add at least two splits with amounts."; return }
        let sum = parsed.reduce(0) { $0 + $1.1 }
        guard abs(sum - total) <= 0.01 * Double(parsed.count) else {
            errorMessage = "Splits must add up to \(Money.format(total, currency: txn.currency ?? store.baseCurrency))."
            return
        }
        let splits: [JSONValue] = parsed.map { .object([
            "categoryId": $0.0.isEmpty ? .null : .string($0.0), "amount": .double($0.1),
        ]) }
        do { try store.apply(.setTransactionSplits, Args(["id": .string(txn.id), "splits": .array(splits)])); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }

    private func removeSplit() {
        do { try store.apply(.setTransactionSplits, Args(["id": .string(txn.id), "splits": .array([])])); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}
