import SwiftUI
import FinchCore

/// A multi-select picker row's value: the selected names joined, or `emptyLabel`
/// when nothing is selected (e.g. "All accounts"). Mirrors `splitSummaryText`.
func multiSelectSummary(names: [String], emptyLabel: String) -> String {
    names.isEmpty ? emptyLabel : names.joined(separator: ", ")
}

/// A form row that shows a multi-selection summary and opens a full-height BOTTOM
/// SHEET with a searchable multi-select list — the multi-select sibling of
/// `SearchablePickerRow` (reuses its `PickerOption`). The sheet STAGES a set and
/// commits it on Confirm; Cancel discards.
struct MultiSelectPickerRow<RowContent: View>: View {
    let title: String
    let glyph: FieldGlyph
    let options: [PickerOption]
    @Binding var selection: Set<String>
    let emptyLabel: String
    /// Draws one option in the sheet — see `SearchablePickerRow.rowContent`.
    @ViewBuilder var rowContent: (PickerOption) -> RowContent
    @State private var presented = false

    private var summary: String {
        multiSelectSummary(names: options.filter { selection.contains($0.id) }.map(\.name), emptyLabel: emptyLabel)
    }

    var body: some View {
        Button { presented = true } label: {
            FieldRow(glyph: glyph, title: LocalizedStringKey(title), isEmpty: false) {
                Text(summary).foregroundStyle(selection.isEmpty ? .secondary : .primary).lineLimit(1).truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            MultiSelectPickerSheet(title: title, options: options, selection: $selection,
                                   rowContent: rowContent)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: searchable, multi-select. Tapping toggles a staged id; Confirm
/// applies the staged set to the binding; Cancel discards.
private struct MultiSelectPickerSheet<RowContent: View>: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: Set<String>
    @ViewBuilder let rowContent: (PickerOption) -> RowContent
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: Set<String>

    init(title: String, options: [PickerOption], selection: Binding<Set<String>>,
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
                    if staged.contains(opt.id) { staged.remove(opt.id) } else { staged.insert(opt.id) }
                } label: {
                    HStack {
                        rowContent(opt)
                        // Tick after any trailing value the row already draws — see
                        // the single-select sheet.
                        Spacer(minLength: 8)
                        if staged.contains(opt.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
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


extension MultiSelectPickerRow where RowContent == Text {
    /// The plain name-only multi-select — tags, categories, anything that is just a name.
    init(title: String, glyph: FieldGlyph, options: [PickerOption],
         selection: Binding<Set<String>>, emptyLabel: String) {
        self.init(title: title, glyph: glyph, options: options, selection: selection,
                  emptyLabel: emptyLabel, rowContent: { Text($0.name) })
    }
}

extension MultiSelectPickerRow where RowContent == AccountPickerRowLabel {
    /// The account multi-select: the Accounts list's own row, icon and balance included.
    init(title: String, glyph: FieldGlyph, accounts: [AccountRow],
         selection: Binding<Set<String>>, emptyLabel: String) {
        self.init(title: title, glyph: glyph,
                  options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") },
                  selection: selection, emptyLabel: emptyLabel,
                  rowContent: { opt in AccountPickerRowLabel(accounts: accounts, id: opt.id, name: opt.name) })
    }
}
