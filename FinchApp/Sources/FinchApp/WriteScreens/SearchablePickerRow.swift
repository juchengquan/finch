import SwiftUI

/// One option in a `SearchablePickerRow` — an id + its display name.
struct PickerOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A form row that shows the current selection and pushes a searchable list to
/// change it — for long lists (categories, accounts) where an inline menu is
/// cramped. Drop-in replacement for a `Picker` bound to a String id.
struct SearchablePickerRow: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String

    private var selectedName: String { options.first { $0.id == selection }?.name ?? "—" }

    var body: some View {
        NavigationLink {
            SearchablePickerList(title: title, options: options, selection: $selection)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(selectedName).foregroundStyle(.secondary)
            }
        }
    }
}

/// The pushed list: searchable, single-select, pops on choose.
private struct SearchablePickerList: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [PickerOption] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List(filtered) { opt in
            Button {
                selection = opt.id
                dismiss()
            } label: {
                HStack {
                    Text(opt.name)
                    Spacer()
                    if opt.id == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
