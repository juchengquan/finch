import SwiftUI

/// Show/hide + reorder the dashboard cards. Enabled cards (in `layout.order`)
/// appear first, reorderable; disabled cards follow. Any edit that no longer
/// matches a template clears `templateName` ("Custom").
struct InsightsCustomizeSheet: View {
    @Binding var layout: InsightsLayout
    @Environment(\.dismiss) private var dismiss

    private var disabled: [String] { InsightsCatalog.all.map(\.id).filter { !layout.order.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Shown") {
                    ForEach(layout.order, id: \.self) { id in row(id) }
                        .onMove { from, to in layout.order.move(fromOffsets: from, toOffset: to); retag() }
                }
                if !disabled.isEmpty {
                    Section("Hidden") { ForEach(disabled, id: \.self) { id in row(id) } }
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
                    retag()
                })).labelsHidden()
        }
    }

    private func retag() { layout.templateName = layout.matchingTemplate()?.rawValue }
}
