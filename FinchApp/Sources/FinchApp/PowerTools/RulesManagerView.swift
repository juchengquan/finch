import SwiftUI
import FinchCore

/// Phase 4 — rules manager: list (with match counts + active toggle), create,
/// edit (simple single-condition/action rules), delete, backfill. Complex rules
/// open read-only. create/update/delete/backfillRule through the chokepoint.
struct RulesManagerView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var creating = false
    @State private var editing: RuleSummary?    // simple rule → editor
    @State private var viewing: RuleSummary?    // complex rule → read-only detail
    @State private var errorMessage: String?

    var body: some View {
        let counts = Selectors.ruleMatchCounts(store.txns, store.activeLedgerId)
        return List {
            if store.rules.isEmpty {
                Text("No rules yet. Rules auto-apply to new income/expense entries.").foregroundStyle(.secondary)
            }
            ForEach(store.rules) { rule in
                HStack {
                    Button { open(rule) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name).foregroundStyle(.primary)
                            Text("priority \(rule.priority)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let n = counts[rule.id], n > 0 {
                        Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityLabel("\(n) transactions")
                    }
                    Toggle("", isOn: Binding(get: { rule.isActive }, set: { setActive(rule, $0) }))
                        .labelsHidden().accessibilityLabel("Active")
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
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rule")
            }
        }
        .sheet(isPresented: $creating) { RuleSheet(rule: nil) }
        .sheet(item: $editing) { RuleSheet(rule: $0) }
        .sheet(item: $viewing) { RuleDetailView(rule: $0) }
    }

    private func open(_ r: RuleSummary) {
        if SimpleRule.parse(conditionJSON: r.conditionJSON, actionsJSON: r.actionsJSON) != nil { editing = r }
        else { viewing = r }
    }
    private func setActive(_ r: RuleSummary, _ on: Bool) {
        do { try store.apply(.updateRule, Args(["id": .string(r.id), "patch": .object(["isActive": .bool(on)])])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ r: RuleSummary) {
        do { try store.apply(.deleteRule, Args(["id": .string(r.id)])) } catch { errorMessage = i18nMessage(error) }
    }
    private func backfill(_ r: RuleSummary) {
        do { try store.apply(.backfillRule, Args(["id": .string(r.id)])) } catch { errorMessage = i18nMessage(error) }
    }
}

/// Create (rule == nil) or edit a simple single-condition/single-action rule.
struct RuleSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let rule: RuleSummary?

    enum Field: String, CaseIterable, Identifiable { case merchant, amount; var id: String { rawValue } }
    enum ActionKind: String, CaseIterable, Identifiable { case setCategory, markReviewed; var id: String { rawValue }
        var label: String { self == .setCategory ? "Set category" : "Mark reviewed" } }

    @State private var name: String
    @State private var field: Field
    @State private var op: String
    @State private var value: String
    @State private var action: ActionKind
    @State private var categoryId: String
    @State private var priority: Int
    @State private var isActive: Bool
    @State private var runOnEdit: Bool
    @State private var errorMessage: String?

    init(rule: RuleSummary?) {
        self.rule = rule
        let form = rule.flatMap { SimpleRule.parse(conditionJSON: $0.conditionJSON, actionsJSON: $0.actionsJSON) }
        _name = State(initialValue: rule?.name ?? "")
        _field = State(initialValue: form.flatMap { Field(rawValue: $0.field.rawValue) } ?? .merchant)
        _op = State(initialValue: form?.op ?? "contains")
        _value = State(initialValue: form?.value ?? "")
        switch form?.action {
        case .setCategory(let cid): _action = State(initialValue: .setCategory); _categoryId = State(initialValue: cid)
        case .markReviewed: _action = State(initialValue: .markReviewed); _categoryId = State(initialValue: "")
        case nil: _action = State(initialValue: .setCategory); _categoryId = State(initialValue: "")
        }
        _priority = State(initialValue: rule?.priority ?? 100)
        _isActive = State(initialValue: rule?.isActive ?? true)
        _runOnEdit = State(initialValue: rule?.runOnEdit ?? false)
    }

    private var ops: [String] { field == .merchant ? ["contains", "equals"] : ["gt", "lt", "equals"] }
    private var isEdit: Bool { rule != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    Stepper("Priority \(priority)", value: $priority, in: 0...1000)
                }
                Section("When") {
                    Picker("Field", selection: $field) { ForEach(Field.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                        .onChange(of: field) { _, _ in if !ops.contains(op) { op = ops[0] } }
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
                Section {
                    Toggle("Run on edit", isOn: $runOnEdit)
                    if isEdit { Toggle("Active", isOn: $isActive) }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(isEdit ? "Edit Rule" : "New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").bold()
                }
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
        let condValue: JSONValue
        if field == .amount {
            guard let parsed = DecimalInput.parse(value) else { errorMessage = "Enter a numeric amount."; return }
            condValue = .double(parsed)
        } else {
            condValue = .string(value)
        }
        let condition: JSONValue = .object(["field": .string(field.rawValue), "op": .string(op), "value": condValue])
        let actions: JSONValue
        switch action {
        case .setCategory:
            guard !categoryId.isEmpty else { errorMessage = "Pick a category."; return }
            actions = .array([.object(["type": .string("set_category"), "categoryId": .string(categoryId)])])
        case .markReviewed:
            actions = .array([.object(["type": .string("mark_reviewed")])])   // fix: engine expects mark_reviewed
        }
        do {
            if let rule {
                try store.apply(.updateRule, Args(["id": .string(rule.id), "patch": .object([
                    "name": .string(name), "priority": .int(priority),
                    "condition": condition, "actions": actions,
                    "isActive": .bool(isActive), "runOnEdit": .bool(runOnEdit),
                ])]))
            } else {
                try store.apply(.createRule, Args([
                    "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                    "condition": condition, "actions": actions,
                    "priority": .int(priority), "runOnEdit": .bool(runOnEdit),
                ]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}

/// Read-only detail for a complex rule the simple builder can't represent.
struct RuleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let rule: RuleSummary

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name", value: rule.name)
                    LabeledContent("Priority", value: "\(rule.priority)")
                    LabeledContent("Active", value: rule.isActive ? "Yes" : "No")
                    LabeledContent("Run on edit", value: rule.runOnEdit ? "Yes" : "No")
                }
                Section("Matches") { Text(conditionSummary) }
                Section("Actions") { Text(actionsSummary) }
                Section {
                    Text("This rule is too complex to edit on iOS. Open it on the web for full control.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var conditionSummary: String {
        guard let v = SimpleRule.jsonValue(rule.conditionJSON), let cond = RuleCondition.parse(v) else { return "—" }
        switch cond {
        case .all(let cs): return "all of \(cs.count) conditions"
        case .any(let cs): return "any of \(cs.count) conditions"
        case .not: return "not (1 condition)"
        case .leaf(let l): return "\(l.field) \(l.op)"
        }
    }
    private var actionsSummary: String {
        guard let v = SimpleRule.jsonValue(rule.actionsJSON), case .array(let arr) = v else { return "—" }
        let types = arr.compactMap { RuleAction.parse($0)?.type }
        return types.isEmpty ? "—" : "\(types.count) action(s): " + types.joined(separator: ", ")
    }
}
