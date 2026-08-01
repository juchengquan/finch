import SwiftUI
import FinchCore

/// One option in a `SearchablePickerRow` — an id + its display name.
struct PickerOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A form row that shows the current selection and opens a full-height BOTTOM
/// SHEET (slides up from the bottom) with a searchable single-select list.
/// Drop-in: same (title, options, selection) API. The sheet STAGES the tapped
/// option and commits it on Confirm (Cancel discards) — no accidental change on
/// a stray tap.
struct SearchablePickerRow<RowContent: View>: View {
    let title: String
    let glyph: FieldGlyph
    let options: [PickerOption]
    @Binding var selection: String
    /// Non-nil ⇒ the sheet also offers a split toggle — the account-payment twin
    /// of `CategoryPickerRow`'s `splitting`: a purchase paid from several of these
    /// options instead of just one. nil ⇒ plain single-select, unchanged (every
    /// other picker built on this type: From/To transfer legs, Adjust Balance's
    /// account, the scheduled-template pickers).
    var splitting: Binding<SplitAllocation>? = nil
    /// Currency for the split section's amount fields (ignored when `splitting`
    /// is nil).
    var currency: String = ""
    /// Draws one option inside the sheet. Defaults to the plain name (see the
    /// convenience init below), so nothing that doesn't care is affected. The
    /// account pickers hand back an `AccountRowView` — REUSING the Accounts list's
    /// row rather than imitating it, so the two cannot drift.
    @ViewBuilder var rowContent: (PickerOption) -> RowContent
    @State private var presented = false

    init(title: String, glyph: FieldGlyph, options: [PickerOption], selection: Binding<String>,
         splitting: Binding<SplitAllocation>? = nil, currency: String = "",
         @ViewBuilder rowContent: @escaping (PickerOption) -> RowContent) {
        self.title = title
        self.glyph = glyph
        self.options = options
        self._selection = selection
        self.splitting = splitting
        self.currency = currency
        self.rowContent = rowContent
    }

    private var selectedName: String { options.first { $0.id == selection }?.name ?? "—" }
    /// Two-plus ticked rows ⇒ the row shows their names joined instead of the
    /// single selection — same rule as `CategoryPickerRow.splitSummary`, derived
    /// here rather than threaded in since `options` already has every name needed.
    private var splitSummary: String? {
        guard let splitting else { return nil }
        return splitSummaryText(names: splitting.wrappedValue.rows.compactMap { row in
            options.first { $0.id == row.id }?.name
        })
    }

    var body: some View {
        Button { presented = true } label: {
            FieldRow(glyph: glyph, title: LocalizedStringKey(title),
                     isEmpty: (splitSummary ?? (selection.isEmpty ? nil : selectedName)) == nil) {
                Text(splitSummary ?? selectedName).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            SearchablePickerSheet(title: title, options: options, selection: $selection,
                                  splitting: splitting, currency: currency, rowContent: rowContent)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

extension SearchablePickerRow where RowContent == Text {
    /// The plain name-only picker — what every non-account caller uses.
    init(title: String, glyph: FieldGlyph, options: [PickerOption], selection: Binding<String>) {
        self.init(title: title, glyph: glyph, options: options, selection: selection,
                  rowContent: { Text($0.name) })
    }
}

extension SearchablePickerRow where RowContent == AccountPickerRowLabel {
    /// The account picker: pass the accounts themselves and the sheet draws the
    /// Accounts list's own row — icon, name, balance. `splitting`/`currency` are
    /// the split-tender affordance — several accounts paying for one purchase;
    /// every other account picker (From/To, Adjust Balance, scheduled templates)
    /// leaves both at their defaults and is unaffected.
    init(title: String, glyph: FieldGlyph, accounts: [AccountRow], selection: Binding<String>,
         splitting: Binding<SplitAllocation>? = nil, currency: String = "") {
        self.init(title: title, glyph: glyph,
                  options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") },
                  selection: selection, splitting: splitting, currency: currency,
                  rowContent: { opt in AccountPickerRowLabel(accounts: accounts, id: opt.id, name: opt.name) })
    }
}

/// One account inside a picker sheet: the Accounts list's row, minus the
/// reconcile seal (bookkeeping hygiene, not a reason to pick an account). Falls
/// back to the bare name if the id no longer resolves — the options and the
/// accounts are handed over together, so that should not happen, but a picker is
/// not the place to trap.
struct AccountPickerRowLabel: View {
    let accounts: [AccountRow]
    let id: String
    let name: String
    var body: some View {
        if let account = accounts.first(where: { $0.id == id }) {
            AccountRowView(account: account, showSeal: false)
        } else {
            Text(name)
        }
    }
}

/// The sheet body: searchable, single-select (or, with `splitting` set, a toggle
/// that turns the list multi-select and collects the ticked rows' amounts above
/// it — the flat-list twin of `CategoryPickerSheet`'s tree). Tapping stages a
/// choice; Confirm applies it to the binding and dismisses; Cancel discards.
private struct SearchablePickerSheet<RowContent: View>: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String
    var splitting: Binding<SplitAllocation>? = nil
    var currency: String = ""
    @ViewBuilder let rowContent: (PickerOption) -> RowContent
    /// Needed for `displayNative` in the split section, same as
    /// `CategoryPickerSheet` — so those amounts honour privacy mode too.
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: String
    @State private var splitOn = false
    /// Per-row text while the user is typing. Rows that are not pinned have theirs
    /// dropped after every mutation so they redisplay the recomputed share.
    @State private var amountText: [String: String] = [:]

    init(title: String, options: [PickerOption], selection: Binding<String>,
         splitting: Binding<SplitAllocation>? = nil, currency: String = "",
         @ViewBuilder rowContent: @escaping (PickerOption) -> RowContent) {
        self.title = title
        self.options = options
        self._selection = selection
        self.splitting = splitting
        self.currency = currency
        self.rowContent = rowContent
        self._staged = State(initialValue: selection.wrappedValue)
    }

    private var filtered: [PickerOption] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if splitting != nil { splitSection }
                ForEach(filtered) { opt in row(opt) }
            }
            .searchable(text: $query)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                // Reopening an already-split transaction lands straight in split mode.
                splitOn = (splitting?.wrappedValue.rows.count ?? 0) >= 2
            }
            .onChange(of: splitOn) { _, on in
                guard let splitting else { return }
                if on {
                    // Seed from the single selection, so the option already picked
                    // becomes row one and holds the whole total.
                    if !staged.isEmpty { splitting.wrappedValue.tick(staged) }
                } else {
                    // Collapse to the largest leg — the same option the row was
                    // already displaying, per the projection's dominant-leg rule.
                    if let dominant = splitting.wrappedValue.dominantId { staged = dominant }
                    splitting.wrappedValue = SplitAllocation(total: splitting.wrappedValue.total)
                }
                amountText.removeAll()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        // Splitting still names a single option — the dominant leg —
                        // so the field stays meaningful even while split.
                        selection = splitOn ? (splitting?.wrappedValue.dominantId ?? staged) : staged
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Confirm")
                        .confirmCheckmarkStyle()
                        .disabled(splitOn && splitting?.wrappedValue.problem != nil)
                }
            }
        }
    }

    /// The toggle, and — once it is on — the ticked options with their amounts.
    @ViewBuilder private var splitSection: some View {
        Section {
            Toggle("Split across accounts", isOn: $splitOn)
                .accessibilityIdentifier("account.splitToggle")
        }
        if splitOn, let splitting {
            Section {
                ForEach(Array(splitting.wrappedValue.rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(name(of: row.id))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // Symbol + field kept tight so they read as one right-aligned
                        // unit, matching the Allocated line below.
                        HStack(spacing: 2) {
                            Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                            TextField("0.00", text: amountBinding(row.id, splitting))
                                .numericInput(amountBinding(row.id, splitting))
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .fixedSize()
                                .accessibilityIdentifier("account.splitAmount.\(index)")
                        }
                    }
                }
                LabeledContent("Allocated") {
                    Text(verbatim: "\(store.displayNative(splitting.wrappedValue.allocated, currency: currency)) / \(store.displayNative(splitting.wrappedValue.total, currency: currency))")
                }
                .accessibilityIdentifier("account.allocated")
                .foregroundStyle(splitting.wrappedValue.problem == nil ? .primary : .secondary)
                if let problem = splitting.wrappedValue.problem {
                    // Say WHY Confirm is blocked, same wording rule as the category
                    // split — the old affordance explained neither its state nor
                    // its purpose.
                    Text(Self.message(for: problem)).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private static func message(for problem: SplitAllocation.Problem) -> LocalizedStringKey {
        switch problem {
        case .needsAmount: return "Enter an amount to split."
        case .needsTwo: return "Give at least two accounts an amount."
        case .sumMismatch: return "Splits must add up to the transaction total."
        }
    }

    private func name(of id: String) -> String {
        options.first { $0.id == id }?.name ?? "—"
    }

    /// Typing pins the row; emptying it unpins so it floats again. After every write
    /// the unpinned rows' buffers are dropped so they show the recomputed share —
    /// except the row being edited, which would otherwise fight the user's keystrokes.
    private func amountBinding(_ id: String, _ alloc: Binding<SplitAllocation>) -> Binding<String> {
        Binding(
            get: {
                if let typed = amountText[id] { return typed }
                let amount = alloc.wrappedValue.rows.first { $0.id == id }?.amount ?? 0
                return amount == 0 ? "" : String(format: "%g", amount)
            },
            set: { newValue in
                amountText[id] = newValue
                if let parsed = DecimalInput.parse(newValue), parsed > 0 {
                    alloc.wrappedValue.setAmount(id, parsed)
                } else {
                    alloc.wrappedValue.setAmount(id, nil)
                }
                for r in alloc.wrappedValue.rows where !r.pinned && r.id != id { amountText[r.id] = nil }
            })
    }

    @ViewBuilder private func row(_ opt: PickerOption) -> some View {
        Button {
            tap(opt.id)
        } label: {
            HStack {
                rowContent(opt)
                // The row may already end in a trailing value (an account's
                // balance), so the tick follows it — `CurrencyPickerRow`'s
                // arrangement, kept identical on purpose.
                Spacer(minLength: 8)
                let isSelected = splitOn ? (splitting?.wrappedValue.isTicked(opt.id) ?? false) : opt.id == staged
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// In split mode a tap toggles membership; otherwise it stages the single choice.
    private func tap(_ id: String) {
        guard splitOn, let splitting else { staged = id; return }
        if splitting.wrappedValue.isTicked(id) {
            splitting.wrappedValue.untick(id)
            amountText[id] = nil
        } else {
            splitting.wrappedValue.tick(id)
        }
        for r in splitting.wrappedValue.rows where !r.pinned { amountText[r.id] = nil }
    }
}
