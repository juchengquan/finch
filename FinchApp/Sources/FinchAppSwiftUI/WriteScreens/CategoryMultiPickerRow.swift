import SwiftUI
import FinchCore

/// A form row that shows the selected categories' summary and opens a full-height
/// BOTTOM SHEET rendering the category HIERARCHY as a MULTI-select tree — the
/// multi-select sibling of `CategoryPickerRow`. Staged-then-Confirm.
struct CategoryMultiPickerRow: View {
    let title: String
    let glyph: FieldGlyph
    let categories: [CategoryRow]
    @Binding var selection: Set<String>
    let emptyLabel: String
    @State private var presented = false

    private var summary: String {
        multiSelectSummary(names: categories.filter { selection.contains($0.id) }.map(\.name), emptyLabel: emptyLabel)
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
            CategoryMultiPickerSheet(title: title, categories: categories, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: a searchable category tree, MULTI-select. Tapping toggles a
/// staged id (checkmark); the chevron expands/collapses parents; search force-
/// expands. Confirm applies the staged set; Cancel discards.
private struct CategoryMultiPickerSheet: View {
    let title: String
    let categories: [CategoryRow]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var staged: Set<String>

    init(title: String, categories: [CategoryRow], selection: Binding<Set<String>>) {
        self.title = title
        self.categories = categories
        self._selection = selection
        self._staged = State(initialValue: selection.wrappedValue)
    }

    private var byId: [String: CategoryRow] { Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }) }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(categories), expanded: expanded, search: query)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { item in
                    CategoryTreeRow(
                        item: item, byId: byId,
                        isSelected: staged.contains(item.row.id),
                        expanded: expanded.contains(item.row.id),
                        searchActive: !query.isEmpty,
                        onTap: {
                            if staged.contains(item.row.id) { staged.remove(item.row.id) } else { staged.insert(item.row.id) }
                        },
                        onToggleExpand: {
                            if expanded.contains(item.row.id) { expanded.remove(item.row.id) } else { expanded.insert(item.row.id) }
                        }
                    )
                }
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button { selection = staged; dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Confirm").confirmCheckmarkStyle()
                }
            }
        }
    }
}
