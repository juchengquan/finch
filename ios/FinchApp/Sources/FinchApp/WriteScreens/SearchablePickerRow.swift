import SwiftUI

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
struct SearchablePickerRow: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String
    @State private var presented = false

    private var selectedName: String { options.first { $0.id == selection }?.name ?? "—" }

    var body: some View {
        Button { presented = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(selectedName).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            SearchablePickerSheet(title: title, options: options, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: searchable, single-select. Tapping stages a choice; Confirm
/// applies it to the binding and dismisses; Cancel discards.
private struct SearchablePickerSheet: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var staged: String

    init(title: String, options: [PickerOption], selection: Binding<String>) {
        self.title = title
        self.options = options
        self._selection = selection
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
                        Text(opt.name)
                        Spacer()
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { selection = staged; dismiss() }.bold()
                }
            }
        }
    }
}
