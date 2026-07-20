import SwiftUI

/// Show/hide + reorder the dashboard cards — the sole way the user shapes the
/// Insights dashboard (there are no preset templates). Enabled cards
/// (`layout.order`) appear first, reorderable; disabled cards follow. "Reset to
/// default" restores the curated starter set.
struct InsightsCustomizeSheet: View {
    @Binding var layout: InsightsLayout
    @Environment(\.dismiss) private var dismiss

    private var disabled: [String] { InsightsCatalog.all.map(\.id).filter { !layout.order.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Shown") {
                    ForEach(layout.order, id: \.self) { id in row(id) }
                        .onMove { from, to in layout.order.move(fromOffsets: from, toOffset: to) }
                }
                if !disabled.isEmpty {
                    Section("Hidden") { ForEach(disabled, id: \.self) { id in row(id) } }
                }
                Section {
                    Button("Reset to default") { layout.order = InsightsLayout.defaultOrder }
                        .disabled(layout.order == InsightsLayout.defaultOrder)
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
            Spacer()
            Toggle("", isOn: Binding(
                get: { layout.order.contains(id) },
                set: { isOn in
                    if isOn { if !layout.order.contains(id) { layout.order.append(id) } }
                    else { layout.order.removeAll { $0 == id } }
                })).labelsHidden()
        }
    }
}
