import SwiftUI
import FinchCore

/// The Category row's value when a transaction is split: the split's category names
/// joined for display, or nil for a single category (fewer than 2 names).
/// E.g. ["Groceries", "Household"] → "Groceries, Household".
func splitSummaryText(categoryNames: [String]) -> String? {
    categoryNames.count >= 2 ? categoryNames.joined(separator: ", ") : nil
}

/// The Category field as a tap-to-open row + bottom sheet that renders the
/// category HIERARCHY — an indented tree with expand/collapse, matching the
/// Settings › Categories page — instead of a flat list. Same staged-then-Confirm
/// contract as `SearchablePickerRow`, so it's a drop-in for the Category row.
/// Any node (parent or leaf) is selectable; a transaction can sit on a parent.
struct CategoryPickerRow: View {
    let title: String
    var glyph: FieldGlyph = .category
    let categories: [CategoryRow]         // kind-filtered rows (sort_order order)
    @Binding var selection: String
    /// Non-nil ⇒ an empty selection ("") is a legal choice shown under this label
    /// (e.g. "None (top level)" for a category's Parent field), offered as the
    /// first row of the sheet. nil ⇒ empty renders as the "—" placeholder.
    var noneLabel: String? = nil
    /// Non-nil ⇒ the transaction is split: the row shows this summary instead of the
    /// picked category name, and tapping the row (or icon) reopens the split editor.
    var splitSummary: String? = nil
    /// Whether the split icon is actionable (a split needs a non-zero amount).
    var splitEnabled: Bool = false
    /// nil ⇒ no split affordance (e.g. refunds); non-nil ⇒ show the trailing split icon.
    var onSplit: (() -> Void)? = nil
    @State private var presented = false

    private var selectedName: String {
        categories.first { $0.id == selection }?.name ?? (selection.isEmpty ? noneLabel : nil) ?? "—"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if splitSummary != nil { onSplit?() } else { presented = true }
            } label: {
                FieldRow(glyph: glyph, title: LocalizedStringKey(title),
                         isEmpty: (splitSummary ?? (selection.isEmpty ? nil : selectedName)) == nil,
                         trailing: {
                    if let onSplit {
                        Button { onSplit() } label: {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.body)
                                .foregroundStyle(splitSummary != nil ? Color.accentColor : Color.secondary)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(splitSummary == nil && !splitEnabled)
                        .opacity(splitSummary == nil && !splitEnabled ? 0.4 : 1)   // dim until an amount exists
                        .accessibilityLabel(splitSummary != nil ? "Edit split" : "Split across categories")
                    }
                    FieldRowChevron()
                }) {
                    Text(splitSummary ?? selectedName).foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $presented) {
            CategoryPickerSheet(title: title, categories: categories, selection: $selection, noneLabel: noneLabel)
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
struct CategoryPickerSheet: View {
    let title: String
    let categories: [CategoryRow]
    @Binding var selection: String
    /// Non-nil ⇒ offer "" as a first, icon-less choice under this label
    /// (used by the Parent field's "None (top level)").
    let noneLabel: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var staged: String

    init(title: String, categories: [CategoryRow], selection: Binding<String>, noneLabel: String? = nil) {
        self.title = title
        self.categories = categories
        self._selection = selection
        self.noneLabel = noneLabel
        self._staged = State(initialValue: selection.wrappedValue)
    }

    private var byId: [String: CategoryRow] { Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) }) }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(categories), expanded: expanded, search: query)
    }

    var body: some View {
        NavigationStack {
            List {
                // The "none" choice isn't a searchable category — hide it while
                // a query filters the tree.
                if let noneLabel, query.isEmpty { noneRow(noneLabel) }
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

    /// The empty-selection row: same geometry as `CategoryTreeRow` (26pt glyph
    /// slot, reserved chevron column) so the list reads as one aligned tree.
    @ViewBuilder private func noneRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            Button { staged = "" } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 20)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                    Text(label).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if staged.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Color.clear.frame(width: 22, height: 30)
        }
    }

    @ViewBuilder private func row(_ item: FlatCategory) -> some View {
        CategoryTreeRow(
            item: item, byId: byId,
            isSelected: item.row.id == staged,
            expanded: expanded.contains(item.row.id),
            searchActive: !query.isEmpty,
            onTap: { staged = item.row.id },
            onToggleExpand: {
                if expanded.contains(item.row.id) { expanded.remove(item.row.id) } else { expanded.insert(item.row.id) }
            }
        )
    }
}

/// One category-tree row shared by the single- and multi-select picker sheets:
/// swatch + icon + indented name + a trailing selection checkmark + an
/// expand/collapse chevron for parents. Selection + expand state are caller-driven.
struct CategoryTreeRow: View {
    let item: FlatCategory
    let byId: [String: CategoryRow]
    let isSelected: Bool
    let expanded: Bool
    let searchActive: Bool
    let onTap: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        let c = item.row
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 26, height: 26)
                        Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                            .font(.system(size: 12)).foregroundStyle(.white)
                    }
                    Text(c.name).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: (expanded || searchActive) ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 22, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(searchActive)   // search force-expands; chevron is inert
            } else {
                // Reserve the chevron slot so checkmarks/edges line up across rows.
                Color.clear.frame(width: 22, height: 30)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 14)
        .contentShape(Rectangle())
    }
}
