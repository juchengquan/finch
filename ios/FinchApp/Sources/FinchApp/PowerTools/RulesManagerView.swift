import SwiftUI
import FinchCore

/// Phase 4 — rules manager: list (match counts + active toggle), create, edit
/// (multi-condition all/any + multi-action, CP1 fields), delete, backfill.
/// Rules using CP2 fields / nested groups / not / split open read-only.
struct RulesManagerView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var creating = false
    @State private var editing: RuleSummary?
    @State private var viewing: RuleSummary?
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
        if RuleParse.parse(conditionJSON: r.conditionJSON, actionsJSON: r.actionsJSON) != nil { editing = r }
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

// CP1 kind values a user can target.
private let kindValues = ["expense", "income", "transfer", "refund", "adjustment"]

private func opsFor(_ f: LeafForm.Field) -> [String] {
    switch f {
    case .merchant: return ["is", "contains", "startsWith"]
    case .note:     return ["contains"]
    case .amount:   return ["gt", "gte", "lt", "lte", "eq", "between"]
    case .kind:     return ["is"]
    }
}
private func opLabel(_ o: String) -> String {
    switch o {
    case "is": return "is"; case "contains": return "contains"; case "startsWith": return "starts with"
    case "gt": return "greater than"; case "gte": return "≥"; case "lt": return "less than"; case "lte": return "≤"
    case "eq": return "equals"; case "between": return "between"; default: return o
    }
}

/// Create (rule == nil) or edit a multi-condition / multi-action rule.
struct RuleSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let rule: RuleSummary?

    // Editable rows (flattened mutable mirror of RuleForm).
    struct CondRow: Identifiable { let id = UUID(); var field: LeafForm.Field = .merchant; var op = "contains"; var value = ""; var value2 = "" }
    enum ActType: String, CaseIterable, Identifiable { case setCategory, setNote, setMerchant, setKind, markReviewed
        var id: String { rawValue }
        var label: String { switch self { case .setCategory: "Set category"; case .setNote: "Set note"; case .setMerchant: "Set merchant"; case .setKind: "Set kind"; case .markReviewed: "Mark reviewed" } } }
    struct ActRow: Identifiable { let id = UUID(); var type: ActType = .setCategory; var categoryId = ""; var text = ""; var kind = "expense" }

    @State private var name: String
    @State private var combinator: RuleForm.Combinator
    @State private var conditions: [CondRow]
    @State private var actions: [ActRow]
    @State private var priority: Int
    @State private var isActive: Bool
    @State private var runOnEdit: Bool
    @State private var errorMessage: String?

    init(rule: RuleSummary?) {
        self.rule = rule
        let form = rule.flatMap { RuleParse.parse(conditionJSON: $0.conditionJSON, actionsJSON: $0.actionsJSON) }
        _name = State(initialValue: rule?.name ?? "")
        _combinator = State(initialValue: form?.combinator ?? .all)
        _conditions = State(initialValue: form.map { $0.conditions.map { lf in
            CondRow(field: lf.field, op: lf.op, value: lf.value, value2: lf.value2)
        } } ?? [CondRow()])
        _actions = State(initialValue: form.map { $0.actions.map(Self.actRow(from:)) } ?? [ActRow()])
        _priority = State(initialValue: rule?.priority ?? 100)
        _isActive = State(initialValue: rule?.isActive ?? true)
        _runOnEdit = State(initialValue: rule?.runOnEdit ?? false)
    }

    private static func actRow(from a: ActionForm) -> ActRow {
        switch a.kind {
        case .setCategory(let id): return ActRow(type: .setCategory, categoryId: id)
        case .setNote(let s):      return ActRow(type: .setNote, text: s)
        case .setMerchant(let s):  return ActRow(type: .setMerchant, text: s)
        case .setKind(let k):      return ActRow(type: .setKind, kind: k)
        case .markReviewed:        return ActRow(type: .markReviewed)
        }
    }

    private var isEdit: Bool { rule != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    Stepper("Priority \(priority)", value: $priority, in: 0...1000)
                }
                Section("When") {
                    if conditions.count > 1 {
                        Picker("Match", selection: $combinator) {
                            Text("all of").tag(RuleForm.Combinator.all); Text("any of").tag(RuleForm.Combinator.any)
                        }.pickerStyle(.segmented)
                    }
                    ForEach($conditions) { $c in condRow($c) }
                        .onDelete { conditions.remove(atOffsets: $0) }
                    Button { conditions.append(CondRow()) } label: { Label("Add condition", systemImage: "plus") }
                }
                Section("Then") {
                    ForEach($actions) { $a in actRow($a) }
                        .onDelete { actions.remove(atOffsets: $0) }
                    Button { actions.append(ActRow()) } label: { Label("Add action", systemImage: "plus") }
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
        }
    }

    @ViewBuilder private func condRow(_ c: Binding<CondRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Field", selection: c.field) {
                ForEach(LeafForm.Field.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .onChange(of: c.wrappedValue.field) { _, f in if !opsFor(f).contains(c.wrappedValue.op) { c.wrappedValue.op = opsFor(f)[0] } }
            Picker("Is", selection: c.op) { ForEach(opsFor(c.wrappedValue.field), id: \.self) { Text(opLabel($0)).tag($0) } }
            switch c.wrappedValue.field {
            case .merchant, .note:
                TextField("Text", text: c.value)
            case .amount:
                TextField("Amount", text: c.value).keyboardType(.decimalPad)
                if c.wrappedValue.op == "between" { TextField("and", text: c.value2).keyboardType(.decimalPad) }
            case .kind:
                Picker("Kind", selection: c.value) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } }
            }
        }
    }

    @ViewBuilder private func actRow(_ a: Binding<ActRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Action", selection: a.type) { ForEach(ActType.allCases) { Text($0.label).tag($0) } }
            switch a.wrappedValue.type {
            case .setCategory:
                Picker("Category", selection: a.categoryId) { ForEach(store.pickableCategories) { Text($0.name).tag($0.id) } }
            case .setNote:     TextField("Note", text: a.text)
            case .setMerchant: TextField("Merchant", text: a.text)
            case .setKind:     Picker("Kind", selection: a.kind) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } }
            case .markReviewed: EmptyView()
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard !conditions.isEmpty else { errorMessage = "Add at least one condition."; return }
        guard !actions.isEmpty else { errorMessage = "Add at least one action."; return }

        // Build condition forms, validating/normalizing amounts to plain decimal.
        var condForms: [LeafForm] = []
        for c in conditions {
            var value = c.value, value2 = c.value2
            switch c.field {
            case .merchant, .note:
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a value for every condition."; return }
            case .kind:
                if value.isEmpty { value = kindValues[0] }
            case .amount:
                guard let d = DecimalInput.parse(value) else { errorMessage = "Enter a numeric amount."; return }
                value = RuleParse.numStr(d)
                if c.op == "between" {
                    guard let hi = DecimalInput.parse(value2) else { errorMessage = "Enter both amounts for 'between'."; return }
                    value2 = RuleParse.numStr(hi)
                }
            }
            condForms.append(LeafForm(field: c.field, op: c.op, value: value, value2: value2))
        }

        // Build action forms.
        var actForms: [ActionForm] = []
        for a in actions {
            switch a.type {
            case .setCategory:
                let cid = a.categoryId.isEmpty ? (store.pickableCategories.first?.id ?? "") : a.categoryId
                guard !cid.isEmpty else { errorMessage = "Pick a category."; return }
                actForms.append(ActionForm(kind: .setCategory(cid)))
            case .setNote:
                guard !a.text.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter the note text."; return }
                actForms.append(ActionForm(kind: .setNote(a.text)))
            case .setMerchant:
                guard !a.text.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter the merchant."; return }
                actForms.append(ActionForm(kind: .setMerchant(a.text)))
            case .setKind:
                actForms.append(ActionForm(kind: .setKind(a.kind.isEmpty ? kindValues[0] : a.kind)))
            case .markReviewed:
                actForms.append(ActionForm(kind: .markReviewed))
            }
        }

        let (condition, actionsJSON) = RuleParse.build(RuleForm(combinator: combinator, conditions: condForms, actions: actForms))
        do {
            if let rule {
                try store.apply(.updateRule, Args(["id": .string(rule.id), "patch": .object([
                    "name": .string(name), "priority": .int(priority),
                    "condition": condition, "actions": actionsJSON,
                    "isActive": .bool(isActive), "runOnEdit": .bool(runOnEdit),
                ])]))
            } else {
                try store.apply(.createRule, Args([
                    "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                    "condition": condition, "actions": actionsJSON,
                    "priority": .int(priority), "runOnEdit": .bool(runOnEdit),
                ]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}

/// Read-only detail for a rule the CP1 builder can't represent.
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
        guard let v = RuleParse.jsonValue(rule.conditionJSON), let cond = RuleCondition.parse(v) else { return "—" }
        switch cond {
        case .all(let cs): return "all of \(cs.count) conditions"
        case .any(let cs): return "any of \(cs.count) conditions"
        case .not: return "not (1 condition)"
        case .leaf(let l): return "\(l.field) \(l.op)"
        }
    }
    private var actionsSummary: String {
        guard let v = RuleParse.jsonValue(rule.actionsJSON), case .array(let arr) = v else { return "—" }
        let types = arr.compactMap { RuleAction.parse($0)?.type }
        return types.isEmpty ? "—" : "\(types.count) action(s): " + types.joined(separator: ", ")
    }
}
