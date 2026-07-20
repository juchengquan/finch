import SwiftUI
import FinchCore

/// The 5th tab (Phase 1.5). Six cards, each driven by a selector over the
/// projected store. All money goes through `Money` / the store helpers.
struct InsightsTab: View {
    @EnvironmentObject private var store: FinchStore
    /// Trends (charts) vs Breakdown (the former Reports page: per-category
    /// monthly spend + CSV export). Mirrors the web Insights view toggle.
    private enum InsightsMode: String, CaseIterable, Identifiable { case trends = "Trends", breakdown = "Breakdown"; var id: String { rawValue } }
    @State private var view: InsightsMode = .trends
    @State private var rangeMonths = 6   // 3M / 6M / 1Y range switcher

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
                                InsightsCard()
                                MonthlySpendingCard(months: rangeMonths)
                                NetWorthCard(months: rangeMonths)
                                CashflowCard(months: rangeMonths)
                                SavingsRateCard()
                                WhatIfCard()
                                CategoryDeltasCard()
                                WeeklyDigestCard()
                                IncomeSankeyCard()
                                SpendingHeatmapCard()
                                NetWorthByTypeCard()
                                CategoryBreakdownCard()
                                TopMerchantsCard()
                                ForecastCard()
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
            }
        }
    }
}
