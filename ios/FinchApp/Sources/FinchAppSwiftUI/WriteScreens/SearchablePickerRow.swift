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
    /// Draws one option inside the sheet. Defaults to the plain name (see the
    /// convenience init below), so nothing that doesn't care is affected. The
    /// account pickers hand back an `AccountRowView` — REUSING the Accounts list's
    /// row rather than imitating it, so the two cannot drift.
    @ViewBuilder var rowContent: (PickerOption) -> RowContent
    @State private var presented = false

    private var selectedName: String { options.first { $0.id == selection }?.name ?? "—" }

    var body: some View {
        Button { presented = true } label: {
            FieldRow(glyph: glyph, title: LocalizedStringKey(title), isEmpty: selection.isEmpty) {
                Text(selectedName).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            SearchablePickerSheet(title: title, options: options, selection: $selection,
                                  rowContent: rowContent)
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
    /// Accounts list's own row — icon, name, balance.
    init(title: String, glyph: FieldGlyph, accounts: [AccountRow], selection: Binding<String>) {
        self.init(title: title, glyph: glyph,
                  options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") },
                  selection: selection,
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

/// The sheet body: searchable, single-select. Tapping stages a choice; Confirm
/// applies it to the binding and dismisses; Cancel discards.
private struct SearchablePickerSheet<RowContent: View>: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String
    @ViewBuilder let rowContent: (PickerOption) -> RowContent
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: String

    init(title: String, options: [PickerOption], selection: Binding<String>,
         @ViewBuilder rowContent: @escaping (PickerOption) -> RowContent) {
        self.title = title
        self.options = options
        self._selection = selection
        self.rowContent = rowContent
        self._staged = State(initialValue: selection.wrappedValue)
    }

    private var filtered: [PickerOption] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { opt in
                Button {
                    staged = opt.id
                } label: {
                    HStack {
                        rowContent(opt)
                        // The row may already end in a trailing value (an account's
                        // balance), so the tick follows it — `CurrencyPickerRow`'s
                        // arrangement, kept identical on purpose.
                        Spacer(minLength: 8)
                        if opt.id == staged { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { selection = staged; dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Confirm").confirmCheckmarkStyle()
                }
            }
        }
    }
}
