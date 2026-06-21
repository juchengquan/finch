import SwiftUI
import FinchCore

// Phase 3 / remediation #23 — true three-column master–detail on regular width
// (iPad / Mac). Only the tabs that have a real list→detail relationship —
// Accounts and Budgets — use three columns: sidebar (sections) │ list │ detail.
// The dashboard / sheet-based tabs (Insights, Settings, Activity, Scheduled)
// keep two columns (sidebar │ full-width content) — a dashboard squeezed into a
// narrow middle column would be worse.
//
// The list columns ARE `AccountsTab`/`BudgetsTab` themselves, run in their
// selection mode (given a `selection` binding by SplitViewShell); the same views
// render the compact push layout when given no binding. See those files.

/// The shared sections sidebar (column 1), driven by the router so deep links /
/// intents / ⌘1–6 keep selecting tabs. Two clusters: the primary work surfaces,
/// then a "More" group for the secondary ones (Activity — which has no compact
/// tab — plus Scheduled & Settings, mirroring the iPhone More tab).
struct SectionSidebar: View {
    @EnvironmentObject private var router: DeepLinkRouter

    private let primary: [AppTab] = [.accounts, .budgets, .insights]
    private let more: [AppTab] = [.activity, .scheduled, .settings]

    var body: some View {
        List(selection: Binding<AppTab?>(
            get: { router.selectedTab },
            set: { if let t = $0 { router.selectedTab = t } })) {
            Section {
                ForEach(primary) { row($0) }
            }
            Section("More") {
                ForEach(more) { row($0) }
            }
        }
        .navigationTitle("finch")
        .listStyle(.sidebar)
    }

    private func row(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.icon).tag(tab)
    }
}

/// Generic three-column container: shared sidebar + a list column + a detail
/// column. The list column drives selection; the detail column reads it.
struct ThreeColumnShell<ListColumn: View, DetailColumn: View>: View {
    @ViewBuilder var list: () -> ListColumn
    @ViewBuilder var detail: () -> DetailColumn
    var body: some View {
        NavigationSplitView {
            SectionSidebar()
        } content: {
            list()
        } detail: {
            detail()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// The detail (third) column placeholder shown until the user picks a row.
struct DetailPlaceholder: View {
    let systemImage: String
    let label: LocalizedStringKey
    var body: some View {
        ContentUnavailableView(label, systemImage: systemImage)
    }
}
