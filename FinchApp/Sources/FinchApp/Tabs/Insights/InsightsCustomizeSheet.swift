import SwiftUI

/// Shape the Insights dashboard — the sole control (there are no preset
/// templates). One reorderable list of every card: the toggle shows/hides it,
/// and drag reorders it (hidden cards included, so an activated card keeps its
/// place). "Reset to default" restores the curated starter set.
struct InsightsCustomizeSheet: View {
    @Binding var layout: InsightsLayout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.order, id: \.self) { id in row(id) }
                        .onMove { from, to in layout.order.move(fromOffsets: from, toOffset: to) }
                } footer: {
                    Text("Toggle a card to show or hide it; drag to reorder. Hidden cards can be reordered too.")
                }
                Section {
                    Button("Reset to default") { layout = .default }
                        .disabled(layout == .default)
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Customize")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Done").confirmCheckmarkStyle()
                }
            }
        }
    }

    @ViewBuilder private func row(_ id: String) -> some View {
        HStack {
            Text(InsightsCatalog.entry(id)?.title ?? id)
                .foregroundStyle(layout.hidden.contains(id) ? .secondary : .primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { !layout.hidden.contains(id) },
                set: { shown in
                    if shown { layout.hidden.remove(id) } else { layout.hidden.insert(id) }
                })).labelsHidden()
        }
    }
}
