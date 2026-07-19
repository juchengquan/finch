import SwiftUI
import FinchCore

/// The Category field as a tap-to-open row + bottom sheet that renders the
/// category HIERARCHY — an indented tree with expand/collapse, matching the
/// Settings › Categories page — instead of a flat list. Same staged-then-Confirm
/// contract as `SearchablePickerRow`, so it's a drop-in for the Category row.
/// Any node (parent or leaf) is selectable; a transaction can sit on a parent.
struct CategoryPickerRow: View {
    let title: String
    let categories: [CategoryRow]         // kind-filtered rows (sort_order order)
    @Binding var selection: String
    @State private var presented = false

    private var selectedName: String { categories.first { $0.id == selection }?.name ?? "—" }

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
            CategoryPickerSheet(title: title, categories: categories, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: a searchable tree, single-select. Tapping a row stages the
/// category (checkmark); the trailing chevron on parents expands/collapses.
/// Starts collapsed (top level only); typing force-expands to reveal matches.
/// Confirm applies the staged id to the binding; Cancel discards.
private struct CategoryPickerSheet: View {
    let title: String
    let categories: [CategoryRow]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var staged: String

    init(title: String, categories: [CategoryRow], selection: Binding<String>) {
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
                ForEach(visible) { item in row(item) }
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

    /// One tree row: swatch + icon + indented name + staged checkmark, plus a
    /// separate expand/collapse chevron for parents. Mirrors CategoriesView's
    /// rowContent (minus the count pill and admin swipe actions).
    @ViewBuilder private func row(_ item: FlatCategory) -> some View {
        let c = item.row
        HStack(spacing: 8) {
            Button { staged = c.id } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 26, height: 26)
                        Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                            .font(.system(size: 12)).foregroundStyle(.white)
                    }
                    Text(c.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if c.id == staged { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.hasChildren {
                Button {
                    if expanded.contains(c.id) { expanded.remove(c.id) } else { expanded.insert(c.id) }
                } label: {
                    Image(systemName: (expanded.contains(c.id) || !query.isEmpty) ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 22, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!query.isEmpty)   // search force-expands; chevron is inert
            } else {
                // Reserve the chevron slot so checkmarks/edges line up across rows.
                Color.clear.frame(width: 22, height: 30)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 14)
        .contentShape(Rectangle())
    }
}
