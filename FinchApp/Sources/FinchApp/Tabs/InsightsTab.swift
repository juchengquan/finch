import SwiftUI
import FinchCore

/// The 5th tab (Phase 1.5). Six cards, each driven by a selector over the
/// projected store. All money goes through `Money` / the store helpers.
struct InsightsTab: View {
    @EnvironmentObject private var store: FinchStore

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
                        VStack(spacing: 16) {
                            MonthlySpendingCard()
                            NetWorthCard()
                            CategoryBreakdownCard()
                            RecentExpensesCard()
                            ForecastCard()
                            if !store.holdings.isEmpty { HoldingsCard() }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Insights")
        }
    }
}

/// Shared card chrome.
private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private let cardPalette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]

private struct MonthlySpendingCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let endMonth = String(store.today.prefix(7))
        let pts = Selectors.monthlySpending(store.txns, store.activeLedgerId, endMonth, 6)
        Card(title: "Monthly spending") {
            BarChart(data: pts.map { BarChart.DataPoint(label: $0.m, value: $0.v, color: .blue) },
                     xLabel: "Month", yLabel: "Spent")
                .frame(height: 180)
        }
    }
}

private struct NetWorthCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let endMonth = String(store.today.prefix(7))
        let pts = Selectors.netWorthByMonth(store.txns, store.accounts, store.activeLedgerId, endMonth, 6)
        Card(title: "Net worth") {
            LineChart(data: pts.map { LineChart.DataPoint(x: $0.m, y: $0.v) },
                      xLabel: "Month", yLabel: "Net worth")
                .frame(height: 180)
        }
    }
}

private struct CategoryBreakdownCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let month = String(store.today.prefix(7))
        let spend = Selectors.categorySpend(store.txns, store.activeLedgerId, month)
        let top = spend.sorted { $0.value > $1.value }.prefix(6)
        let data = Array(top.enumerated()).map { i, kv in
            Donut.DataPoint(label: store.categoryName(kv.key) ?? kv.key, value: kv.value,
                            color: cardPalette[i % cardPalette.count])
        }
        Card(title: "Spending by category") {
            if data.isEmpty {
                Text("No spending this month").font(.caption).foregroundStyle(.secondary)
            } else {
                Donut(data: data, centerLabel: "This month").frame(height: 200)
            }
        }
    }
}

private struct RecentExpensesCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let rows = Selectors.recentExpenses(store.txns, store.activeLedgerId, 5)
        Card(title: "Recent expenses") {
            if rows.isEmpty {
                Text("Nothing yet").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.merchant)
                            Spacer()
                            // amount is a positive magnitude → render as a spend.
                            Text(Money.format(-r.amount, currency: r.currency)).fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }
}

private struct ForecastCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let month = String(store.today.prefix(7))
        // scheduled = [] — scheduled-template projection is deferred; this is the
        // month-to-date + run-rate forecast.
        Card(title: "This month's forecast") {
            if let f = Selectors.monthForecast(store.txns, [], store.activeLedgerId, month, store.today) {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Spent so far", value: store.displayMoneyBase(f.mtdSpent))
                    LabeledContent("Projected", value: store.displayMoneyBase(f.projected))
                    Text("\(f.daysRemaining) days left").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HoldingsCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        Card(title: "Holdings") {
            VStack(spacing: 6) {
                ForEach(Array(store.holdings.enumerated()), id: \.offset) { _, h in
                    HStack {
                        Text(h.symbol)
                        Spacer()
                        Text(Selectors.holdingValue(h).map { Money.format($0, currency: h.currency) } ?? "—")
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }
}
