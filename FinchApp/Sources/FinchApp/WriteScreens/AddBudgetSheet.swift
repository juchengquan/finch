import SwiftUI
import FinchCore

/// Add a budget via createBudget. Expense budgets track spend against a set of
/// categories; income budgets track received income. Covers name, type, amount,
/// frequency, and (for expense) a multi-select of categories. Routes
/// FinchStore.apply.
struct AddBudgetSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    let frequencies = ["weekly", "monthly", "quarterly", "yearly"]

    @State private var name = ""
    @State private var kind: Kind = .expense
    @State private var amount = ""
    @State private var frequency = "monthly"
    @State private var selectedCategories: Set<String> = []
    @State private var errorMessage: String?

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) { ForEach(Kind.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                    HStack {
                        Text("Amount"); Spacer()
                        TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                Section {
                    ForEach(categories) { cat in
                        Button { toggle(cat.id) } label: {
                            HStack {
                                Text(cat.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedCategories.contains(cat.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text(kind == .income ? "Income categories" : "Categories")
                } footer: {
                    Text("Leave empty to track all \(kind.rawValue) categories.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Add Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedCategories.contains(id) { selectedCategories.remove(id) } else { selectedCategories.insert(id) }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard let value = Double(amount), value > 0 else { errorMessage = "Enter an amount."; return }
        var args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "name": .string(name),
            "type": .string(kind.rawValue), "amount": .double(value), "frequency": .string(frequency),
        ]
        if !selectedCategories.isEmpty {
            args["categoryIds"] = .array(selectedCategories.sorted().map { .string($0) })
        }
        do {
            try store.apply(.createBudget, Args(args))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
