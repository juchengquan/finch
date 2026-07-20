import SwiftUI
import FinchCore

/// The 5th tab. Trends renders a customizable set of cards driven by the saved
/// `InsightsLayout` (template presets, per-device via `@AppStorage`) through the
/// `InsightsCatalog` registry; Breakdown is the per-category monthly report +
/// export. All money goes through `Money` / the store helpers.
struct InsightsTab: View {
    @EnvironmentObject private var store: FinchStore
    /// Trends (charts) vs Breakdown (the former Reports page: per-category
    /// monthly spend + CSV export). Mirrors the web Insights view toggle.
    private enum InsightsMode: String, CaseIterable, Identifiable { case trends = "Trends", breakdown = "Breakdown"; var id: String { rawValue } }
    @State private var view: InsightsMode = .trends
    @State private var rangeMonths = 6   // 3M / 6M / 1Y range switcher
    @AppStorage("finch.insights.layout") private var layout = InsightsLayout.default
    @State private var customizing = false

    var body: some View {
        NavigationStack {
            Group {
                if store.txns.isEmpty && store.accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No insights yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Import a .finch pack from Settings to see insights.")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {   // lazy: off-screen cards (+ their selectors) don't compute until scrolled
                            Picker("View", selection: $view) {
                                ForEach(InsightsMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if view == .trends {
                                Picker("Range", selection: $rangeMonths) {
                                    Text("3M").tag(3); Text("6M").tag(6); Text("1Y").tag(12)
                                }
                                .pickerStyle(.segmented)
                                ForEach(layout.shownOrder, id: \.self) { id in
                                    if let entry = InsightsCatalog.entry(id) {
                                        entry.make(rangeMonths)
                                    }
                                }
                            } else {
                                BreakdownView()
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Insights")
            .ledgerPush()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }   // .topBarLeading is iOS-only; books.vertical is compact-only (macOS uses the sidebar)
                #endif
                ToolbarItem(placement: .primaryAction) { PrivacyToggleButton() }
                // Customize the Trends dashboard (show/hide + reorder), in a ⋯ menu
                // to the right of the privacy (eye) toggle. Trends-only.
                ToolbarItem(placement: .primaryAction) {
                    if view == .trends {
                        Menu {
                            Button { customizing = true } label: { Label("Customize…", systemImage: "slider.horizontal.3") }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            .sheet(isPresented: $customizing) {
                InsightsCustomizeSheet(layout: $layout)
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
    }
}
