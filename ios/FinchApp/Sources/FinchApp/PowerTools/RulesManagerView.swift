import SwiftUI
import FinchCore

/// Phase 4 — rules manager: list (match counts + active toggle), create, edit
/// (multi-condition all/any + multi-action, CP1 fields), delete, backfill.
/// Rules using CP2 fields / nested groups / not / split open read-only.
struct RulesManagerView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var pendingDelete: RuleSummary?   // rule awaiting delete confirmation
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
                    // Not role: .destructive — fake removal animation pre-confirm.
                    Button { pendingDelete = rule } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                }
                .swipeActions(edge: .leading) {
                    Button { backfill(rule) } label: { Label("Backfill", systemImage: "arrow.triangle.2.circlepath") }.tint(.blue)
                }
                .contextMenu {
                    Button { backfill(rule) } label: { Label("Backfill", systemImage: "arrow.triangle.2.circlepath") }
                    Button(role: .destructive) { pendingDelete = rule } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Rules")
        // Centered ALERT (window-level) — see ActivityTab's delete alert.
        .alert("Delete rule?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { r in
            Button("Delete", role: .destructive) { delete(r) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes the rule.")
        }
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
    case .merchant:       return ["is", "contains", "startsWith"]
    case .note:           return ["contains"]
    case .amount:         return ["gt", "gte", "lt", "lte", "eq", "between"]
    case .kind:           return ["is", "in"]
    case .categoryId:     return ["is", "is_null", "in"]
    case .accountId:      return ["is", "in"]
    case .counterpartyId: return ["is", "is_null"]
    case .currency:       return ["is"]
    case .tagId:          return ["has", "has_any", "has_all"]
    case .dateDom:        return ["eq", "gte", "lte"]
    case .dateDow:        return ["in"]
    }
}
private func opLabel(_ o: String) -> String {
    switch o {
    case "is": return "is"; case "contains": return "contains"; case "startsWith": return "starts with"
    case "gt": return "greater than"; case "gte": return "≥"; case "lt": return "less than"; case "lte": return "≤"
    case "eq": return "equals"; case "between": return "between"
    case "is_null": return "is not set"; case "has": return "has tag"
    case "in": return "in"; case "has_any": return "has any of"; case "has_all": return "has all of"; default: return o
    }
}
private func fieldLabel(_ f: LeafForm.Field) -> String {
    switch f {
    case .merchant: return "Merchant"; case .note: return "Note"; case .amount: return "Amount"; case .kind: return "Kind"
    case .categoryId: return "Category"; case .accountId: return "Account"; case .counterpartyId: return "Counterparty"
    case .currency: return "Currency"; case .tagId: return "Tag"; case .dateDom: return "Day of month"; case .dateDow: return "Day of week"
    }
}
// date_dow weekday indices: 0=Sun … 6=Sat (engine dayOfWeek = Calendar(.weekday, UTC) - 1).
private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
private struct PickItem: Identifiable { let id: String; let name: String }

/// A searchable checkmark list that toggles ids in a `[String]` selection.
private struct MultiSelectList: View {
    let title: String
    @Binding var selected: [String]
    let items: [PickItem]
    @State private var query = ""

    var body: some View {
        List {
            ForEach(filtered) { item in
                Button {
                    if let i = selected.firstIndex(of: item.id) { selected.remove(at: i) } else { selected.append(item.id) }
                } label: {
                    HStack {
                        Text(item.name).foregroundStyle(.primary)
                        Spacer()
                        if selected.contains(item.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    private var filtered: [PickItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}

/// Create (rule == nil) or edit a multi-condition / multi-action rule.
struct RuleSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let rule: RuleSummary?

    // Editable rows (flattened mutable mirror of RuleForm).
    struct CondRow: Identifiable { let id = UUID(); var field: LeafForm.Field = .merchant; var op = "contains"; var value = ""; var value2 = ""; var values: [String] = [] }
    enum ActType: String, CaseIterable, Identifiable {
        case setCategory, setNote, setMerchant, setKind, markReviewed, addTag, removeTag, setCounterparty
        var id: String { rawValue }
        var label: String { switch self {
            case .setCategory: "Set category"; case .setNote: "Set note"; case .setMerchant: "Set merchant"
            case .setKind: "Set kind"; case .markReviewed: "Mark reviewed"
            case .addTag: "Add tag"; case .removeTag: "Remove tag"; case .setCounterparty: "Set counterparty" } } }
    struct ActRow: Identifiable { let id = UUID(); var type: ActType = .setCategory; var categoryId = ""; var text = ""; var kind = "expense"; var tagId = ""; var counterpartyId = "" }

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
            CondRow(field: lf.field, op: lf.op, value: lf.value, value2: lf.value2, values: lf.values)
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
        case .addTag(let id):      return ActRow(type: .addTag, tagId: id)
        case .removeTag(let id):   return ActRow(type: .removeTag, tagId: id)
        case .setCounterparty(let id): return ActRow(type: .setCounterparty, counterpartyId: id)
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
            .finchSectionSpacing()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").confirmCheckmarkStyle()
                }
            }
        }
    }

    @ViewBuilder private func condRow(_ c: Binding<CondRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Field", selection: c.field) {
                ForEach(LeafForm.Field.allCases, id: \.self) { Text(fieldLabel($0)).tag($0) }
            }
            .onChange(of: c.wrappedValue.field) { _, f in if !opsFor(f).contains(c.wrappedValue.op) { c.wrappedValue.op = opsFor(f)[0] } }
            Picker("Is", selection: c.op) { ForEach(opsFor(c.wrappedValue.field), id: \.self) { Text(opLabel($0)).tag($0) } }
            switch c.wrappedValue.field {
            case .merchant, .note:
                TextField("Text", text: c.value)
            case .amount:
                TextField("Amount", text: c.value).numericInput(c.value).keyboardType(.decimalPad)
                if c.wrappedValue.op == "between" { TextField("and", text: c.value2).numericInput(c.value2).keyboardType(.decimalPad) }
            case .kind:
                if c.wrappedValue.op == "in" { multiSelect("Kinds", c.values, kindValues.map { PickItem(id: $0, name: $0.capitalized) }) }
                else { Picker("Kind", selection: c.value) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } } }
            case .categoryId:
                if c.wrappedValue.op == "is_null" { EmptyView() }
                else if c.wrappedValue.op == "in" { multiSelect("Categories", c.values, store.pickableCategories.map { PickItem(id: $0.id, name: $0.name) }) }
                else { entityPicker("Category", c.value, store.pickableCategories.map { PickItem(id: $0.id, name: $0.name) }) }
            case .accountId:
                if c.wrappedValue.op == "in" { multiSelect("Accounts", c.values, store.accounts.map { PickItem(id: $0.id, name: $0.name ?? $0.id) }) }
                else { entityPicker("Account", c.value, store.accounts.map { PickItem(id: $0.id, name: $0.name ?? $0.id) }) }
            case .counterpartyId:
                if c.wrappedValue.op != "is_null" { entityPicker("Counterparty", c.value, store.counterparties.map { PickItem(id: $0.id, name: $0.name) }) }
            case .currency:
                entityPicker("Currency", c.value, store.availableDisplayCurrencies.map { PickItem(id: $0, name: $0) })
            case .tagId:
                if c.wrappedValue.op == "has" { entityPicker("Tag", c.value, store.tags.map { PickItem(id: $0.id, name: $0.name) }) }
                else { multiSelect("Tags", c.values, store.tags.map { PickItem(id: $0.id, name: $0.name) }) }
            case .dateDom:
                TextField("Day (1–31)", text: c.value).numericInput(c.value, allowsDecimal: false).keyboardType(.numberPad)
            case .dateDow:
                weekdayChips(c.values)
            }
        }
    }

    /// Inline menu Picker that displays the first item when nothing is chosen yet
    /// (a fresh row starts empty), so the Picker never shows a blank selection.
    /// `save()` applies the same first-item fallback, so the two stay in sync.
    @ViewBuilder private func entityPicker(_ title: String, _ sel: Binding<String>, _ items: [PickItem]) -> some View {
        Picker(title, selection: Binding(
            get: { sel.wrappedValue.isEmpty ? (items.first?.id ?? "") : sel.wrappedValue },
            set: { sel.wrappedValue = $0 })) {
            ForEach(items) { Text($0.name).tag($0.id) }
        }
    }

    /// A pushed, searchable multi-select that summarizes the count inline.
    @ViewBuilder private func multiSelect(_ title: String, _ sel: Binding<[String]>, _ items: [PickItem]) -> some View {
        #if os(iOS)
        UIKitNavLink {
            MultiSelectList(title: title, selected: sel, items: items)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(sel.wrappedValue.isEmpty ? "None" : "\(sel.wrappedValue.count) selected").foregroundStyle(.secondary)
            }
        }
        #else
        NavigationLink {
            MultiSelectList(title: title, selected: sel, items: items)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(sel.wrappedValue.isEmpty ? "None" : "\(sel.wrappedValue.count) selected").foregroundStyle(.secondary)
            }
        }
        #endif
    }

    /// Inline Sun–Sat chips toggling weekday indices (0–6) in the selection.
    @ViewBuilder private func weekdayChips(_ sel: Binding<[String]>) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let key = String(i)
                let on = sel.wrappedValue.contains(key)
                Text(weekdayLabels[i])
                    .font(.caption).frame(maxWidth: .infinity, minHeight: 32)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let idx = sel.wrappedValue.firstIndex(of: key) { sel.wrappedValue.remove(at: idx) }
                        else { sel.wrappedValue.append(key) }
                    }
            }
        }
    }

    @ViewBuilder private func actRow(_ a: Binding<ActRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Action", selection: a.type) { ForEach(ActType.allCases) { Text($0.label).tag($0) } }
            switch a.wrappedValue.type {
            case .setCategory:
                entityPicker("Category", a.categoryId, store.pickableCategories.map { PickItem(id: $0.id, name: $0.name) })
            case .setNote:     TextField("Note", text: a.text)
            case .setMerchant: TextField("Merchant", text: a.text)
            case .setKind:     Picker("Kind", selection: a.kind) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } }
            case .markReviewed: EmptyView()
            case .addTag, .removeTag:
                entityPicker("Tag", a.tagId, store.tags.map { PickItem(id: $0.id, name: $0.name) })
            case .setCounterparty:
                entityPicker("Counterparty", a.counterpartyId, store.counterparties.map { PickItem(id: $0.id, name: $0.name) })
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
            // Array-valued ops (CP2b): require a non-empty selection; value/value2 unused.
            if c.op == "in" || c.op == "has_any" || c.op == "has_all" {
                guard !c.values.isEmpty else { errorMessage = "Select at least one value for every condition."; return }
                condForms.append(LeafForm(field: c.field, op: c.op, value: "", values: c.values))
                continue
            }
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
            case .dateDom:
                guard let n = Int(value), (1...31).contains(n) else { errorMessage = "Enter a day 1–31."; return }
                value = String(n)
            case .categoryId, .counterpartyId:
                if c.op == "is_null" { value = "" }
                else {
                    if value.isEmpty { value = firstId(for: c.field) }
                    guard !value.isEmpty else { errorMessage = "Pick a value for every condition."; return }
                }
            case .accountId, .currency, .tagId:
                if value.isEmpty { value = firstId(for: c.field) }
                guard !value.isEmpty else { errorMessage = "Pick a value for every condition."; return }
            case .dateDow:
                break   // date_dow's only op is `in`, handled by the array-op branch above
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
            case .addTag, .removeTag:
                let tid = a.tagId.isEmpty ? (store.tags.first?.id ?? "") : a.tagId
                guard !tid.isEmpty else { errorMessage = "Pick a tag."; return }
                actForms.append(ActionForm(kind: a.type == .addTag ? .addTag(tid) : .removeTag(tid)))
            case .setCounterparty:
                let cid = a.counterpartyId.isEmpty ? (store.counterparties.first?.id ?? "") : a.counterpartyId
                guard !cid.isEmpty else { errorMessage = "Pick a counterparty."; return }
                actForms.append(ActionForm(kind: .setCounterparty(cid)))
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

    private func firstId(for field: LeafForm.Field) -> String {
        switch field {
        case .categoryId:     return store.pickableCategories.first?.id ?? ""
        case .accountId:      return store.accounts.first?.id ?? ""
        case .counterpartyId: return store.counterparties.first?.id ?? ""
        case .currency:       return store.availableDisplayCurrencies.first ?? ""
        case .tagId:          return store.tags.first?.id ?? ""
        default:              return ""
        }
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
            .finchSectionSpacing()
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
