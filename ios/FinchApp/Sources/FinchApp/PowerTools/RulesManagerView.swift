import SwiftUI
import FinchCore

/// Phase 4 (rules engine) — the rules manager: list, toggle active, delete,
/// backfill, and a simple single-condition / single-action builder. The rules
/// engine + backfill already live in FinchCore (Phase 2); this is the UI.
/// createRule / updateRule / deleteRule / backfillRule through the chokepoint.
struct RulesManagerView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.rules.isEmpty {
                Text("No rules yet. Rules auto-apply to new income/expense entries.").foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            ForEach(store.rules) { rule in
                HStack {
                    Toggle(isOn: Binding(get: { rule.isActive }, set: { setActive(rule, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                            Text("priority \(rule.priority)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(rule) } label: { Label("Delete", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    Button { backfill(rule) } label: { Label("Backfill", systemImage: "arrow.triangle.2.circlepath") }.tint(.blue)
                }
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rule")
            }
        }
        .sheet(isPresented: $showingAdd) { AddRuleSheet() }
    }

    private func setActive(_ r: RuleSummary, _ on: Bool) {
        do { try store.apply(.updateRule, Args(["id": .string(r.id), "patch": .object(["isActive": .bool(on)])])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ r: RuleSummary) {
        do { try store.apply(.deleteRule, Args(["id": .string(r.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func backfill(_ r: RuleSummary) {
        do { try store.apply(.backfillRule, Args(["id": .string(r.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// A single-condition / single-action rule builder (the common case). Advanced
/// all/any/not trees + splits are deferred (the engine supports them).
struct AddRuleSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    enum Field: String, CaseIterable, Identifiable { case merchant, amount; var id: String { rawValue } }
    enum ActionKind: String, CaseIterable, Identifiable { case setCategory, markReviewed; var id: String { rawValue }
        var label: String { self == .setCategory ? "Set category" : "Mark reviewed" } }

    @State private var name = ""
    @State private var field: Field = .merchant
    @State private var op = "contains"
    @State private var value = ""
    @State private var action: ActionKind = .setCategory
    @State private var categoryId = ""
    @State private var errorMessage: String?

    private var ops: [String] { field == .merchant ? ["contains", "equals"] : ["gt", "lt", "equals"] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") { TextField("Name", text: $name) }
                Section("When") {
                    Picker("Field", selection: $field) { ForEach(Field.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                        .onChange(of: field) { _, _ in op = ops[0] }
                    Picker("Is", selection: $op) { ForEach(ops, id: \.self) { Text(opLabel($0)).tag($0) } }
                    TextField(field == .merchant ? "Text" : "Amount", text: $value)
                        .keyboardType(field == .merchant ? .default : .decimalPad)
                }
                Section("Then") {
                    Picker("Action", selection: $action) { ForEach(ActionKind.allCases) { Text($0.label).tag($0) } }
                    if action == .setCategory {
                        Picker("Category", selection: $categoryId) {
                            ForEach(store.pickableCategories) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onAppear { if categoryId.isEmpty { categoryId = store.pickableCategories.first?.id ?? "" } }
        }
    }

    private func opLabel(_ o: String) -> String {
        switch o { case "contains": return "contains"; case "equals": return "equals"
        case "gt": return "greater than"; case "lt": return "less than"; default: return o }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a value."; return }

        let condValue: JSONValue = field == .amount ? .double(Double(value) ?? 0) : .string(value)
        let condition: JSONValue = .object(["field": .string(field.rawValue), "op": .string(op), "value": condValue])
        let actions: JSONValue
        switch action {
        case .setCategory:
            guard !categoryId.isEmpty else { errorMessage = "Pick a category."; return }
            actions = .array([.object(["type": .string("set_category"), "categoryId": .string(categoryId)])])
        case .markReviewed:
            actions = .array([.object(["type": .string("set_reviewed")])])
        }
        do {
            try store.apply(.createRule, Args([
                "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                "condition": condition, "actions": actions]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
