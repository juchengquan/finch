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
    /// True while the OTHER split (category) already has 2+ funded rows — the
    /// engine refuses an entry that is split both ways at once
    /// (`error.split.multiAccount`, Task 4b), so the UI must not let the user
    /// reach that state rather than surface the engine's refusal after a save
    /// half-applies. Disables the toggle; ignored when `splitting` is nil.
    /// Account ids that cannot join a split because their own currency doesn't
    /// match `currency` — the split assumes one currency across every row (see
    /// `AddTransactionSheet.accountSplitArgs`), so mixing would have the engine
    /// silently misread a typed amount as the wrong currency. Ignored when
    /// `splitting` is nil.
    var splitCurrencyMismatch: Set<String> = []
    /// Draws one option inside the sheet. Defaults to the plain name (see the
    /// convenience init below), so nothing that doesn't care is affected. The
    /// account pickers hand back an `AccountRowView` — REUSING the Accounts list's
    /// row rather than imitating it, so the two cannot drift.
    @ViewBuilder var rowContent: (PickerOption) -> RowContent
    @State private var presented = false

    init(title: String, glyph: FieldGlyph, options: [PickerOption], selection: Binding<String>,
         splitting: Binding<SplitAllocation>? = nil, currency: String = "",
         splitCurrencyMismatch: Set<String> = [],
         @ViewBuilder rowContent: @escaping (PickerOption) -> RowContent) {
        self.title = title
        self.glyph = glyph
        self.options = options
        self._selection = selection
        self.splitting = splitting
        self.currency = currency
        self.splitCurrencyMismatch = splitCurrencyMismatch
        self.rowContent = rowContent
    }

    private var selectedName: String { options.first { $0.id == selection }?.name ?? "—" }
    /// Two-plus FUNDED rows ⇒ the row shows their names joined instead of the
    /// single selection — same rule as `CategoryPickerRow.splitSummary`, derived
    /// here rather than threaded in since `options` already has every name needed.
    /// Reads `payload` (funded rows), not `rows` (every ticked row): `Save` gates
    /// on `payload.count >= 2`, so a ticked-but-zero-amount row (e.g. a second tick
    /// whose whole share was pinned away to another row) must not show as a split
    /// here when it will save as a single account.
    private var splitSummary: String? {
        guard let splitting else { return nil }
        return splitSummaryText(names: Self.namesFor(payload: splitting.wrappedValue.payload, options: options))
    }

    /// Pulled out of `splitSummary` so it's directly testable: the names for a
    /// split's FUNDED rows, in payload order. Options that no longer resolve are
    /// dropped rather than shown blank.
    static func namesFor(payload: [(id: String?, amount: Double)], options: [PickerOption]) -> [String] {
        payload.compactMap { row in row.id.flatMap { id in options.first { $0.id == id }?.name } }
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
                                  splitting: splitting, currency: currency,
                                  splitCurrencyMismatch: splitCurrencyMismatch, rowContent: rowContent)
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
    /// Accounts list's own row — icon, name, balance. `splitting`/`currency`/
    /// The split-tender affordance — several accounts paying
    /// for one purchase; every other account picker (From/To, Adjust Balance,
    /// scheduled templates) leaves all three at their defaults and is unaffected.
    /// `splitCurrencyMismatch` is derived here (from `accounts`), not passed by
    /// the caller — it's purely a function of the account list and `currency`.
    init(title: String, glyph: FieldGlyph, accounts: [AccountRow], selection: Binding<String>,
         splitting: Binding<SplitAllocation>? = nil, currency: String = "") {
        self.init(title: title, glyph: glyph,
                  options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") },
                  selection: selection, splitting: splitting, currency: currency,
                  splitCurrencyMismatch: Self.currencyMismatchedAccountIds(accounts, transactionCurrency: currency),
                  rowContent: { opt in AccountPickerRowLabel(accounts: accounts, id: opt.id, name: opt.name) })
    }

    /// Accounts whose own currency differs from `transactionCurrency` — see
    /// `splitCurrencyMismatch`'s doc comment for why these are excluded from a
    /// split. Empty currency ⇒ no restriction (nothing to compare against yet).
    static func currencyMismatchedAccountIds(_ accounts: [AccountRow], transactionCurrency: String) -> Set<String> {
        guard !transactionCurrency.isEmpty else { return [] }
        return Set(accounts.filter { ($0.currency ?? transactionCurrency) != transactionCurrency }.map(\.id))
    }
}

/// One account inside a picker sheet: the Accounts list's own row, minus the
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
    var splitCurrencyMismatch: Set<String> = []
    @ViewBuilder let rowContent: (PickerOption) -> RowContent
    /// Needed for `displayNative` in the split section, same as
    /// `CategoryPickerSheet` — so those amounts honour privacy mode too.
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: String
    @State private var splitOn = false

    init(title: String, options: [PickerOption], selection: Binding<String>,
         splitting: Binding<SplitAllocation>? = nil, currency: String = "",
         splitCurrencyMismatch: Set<String> = [],
         @ViewBuilder rowContent: @escaping (PickerOption) -> RowContent) {
        self.title = title
        self.options = options
        self._selection = selection
        self.splitting = splitting
        self.currency = currency
        self.splitCurrencyMismatch = splitCurrencyMismatch
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
                }
            }
        }
    }

    /// The toggle. Turning it on makes the list multi-select; the AMOUNTS are
    /// page 2's job, so nothing here asks for one.
    ///
    /// This sheet used to host a second amount editor — per-row fields, an
    /// Allocated line and a blocking check — duplicating page 2 and disagreeing
    /// with it the moment either was edited. Page 1 selects; page 2 divides.
    @ViewBuilder private var splitSection: some View {
        Section {
            Toggle("Split across accounts", isOn: $splitOn)
                .accessibilityIdentifier("account.splitToggle")
            if splitOn, !splitCurrencyMismatch.isEmpty {
                Text("Only \(currency) accounts can be part of a split.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }


    private func name(of id: String) -> String {
        options.first { $0.id == id }?.name ?? "—"
    }

    /// Typing pins the row; emptying it unpins so it floats again. After every write
    /// the unpinned rows' buffers are dropped so they show the recomputed share —
    /// except the row being edited, which would otherwise fight the user's keystrokes.

    @ViewBuilder private func row(_ opt: PickerOption) -> some View {
        // A currency-mismatched account can't join a split — only enforced WHILE
        // actually splitting; the plain single-select list is unrestricted.
        let mismatched = splitOn && splitCurrencyMismatch.contains(opt.id)
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
            .opacity(mismatched ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(mismatched)
    }

    /// In split mode a tap toggles membership; otherwise it stages the single choice.
    private func tap(_ id: String) {
        guard splitOn, let splitting else { staged = id; return }
        if splitting.wrappedValue.isTicked(id) {
            splitting.wrappedValue.untick(id)
        } else {
            splitting.wrappedValue.tick(id)
        }
    }
}
