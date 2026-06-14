import SwiftUI
import FinchCore

/// The 5th tab (Phase 1.5). Six cards, each driven by a selector over the
/// projected store. All money goes through `Money` / the store helpers.
struct InsightsTab: View {
    @EnvironmentObject private var store: FinchStore
    /// Trends (charts) vs Breakdown (the former Reports page: per-category
    /// monthly spend + CSV export). Mirrors the web Insights view toggle.
    private enum View_: String, CaseIterable, Identifiable { case trends = "Trends", breakdown = "Breakdown"; var id: String { rawValue } }
    @State private var view: View_ = .trends

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
                            Picker("View", selection: $view) {
                                ForEach(View_.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if view == .trends {
                                MonthlySpendingCard()
                                NetWorthCard()
                                CategoryBreakdownCard()
                                RecentExpensesCard()
                                ForecastCard()
                                if !store.holdings.isEmpty { HoldingsCard() }
                            } else {
                                BreakdownView()
                            }
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
        // MTD + run-rate + remaining scheduled (the upcoming-bills term).
        Card(title: "This month's forecast") {
            if let f = Selectors.monthForecast(store.txns, store.scheduled, store.activeLedgerId, month, store.today) {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Spent so far", value: store.displayMoneyBase(f.mtdSpent))
                    if f.scheduledRest > 0 {
                        LabeledContent("Upcoming scheduled", value: store.displayMoneyBase(f.scheduledRest))
                    }
                    LabeledContent("Projected", value: store.displayMoneyBase(f.projected))
                    Text("\(f.daysRemaining) days left").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
private func monthLabel(_ ym: String) -> String {
    guard ym.count >= 7, let mi = Int(ym.suffix(2)), (1...12).contains(mi) else { return ym }
    return "\(monthNames[mi - 1]) \(ym.prefix(4))"
}

/// The former Reports page, ported as the Insights "Breakdown" view: a month
/// picker (months with data, newest first), the per-category spend list for
/// that month, and a transactions-CSV export scoped to the month.
private struct BreakdownView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var pickedMonth = ""
    @State private var exported: ExportedCsv?

    private func monthsWithData() -> [String] {
        var set = Set<String>()
        for t in store.txns where (t.ledgerId ?? "personal") == store.activeLedgerId { set.insert(String(t.date.prefix(7))) }
        return set.sorted(by: >)
    }

    var body: some View {
        let months = monthsWithData()
        // The pick is the source of truth; if it falls out of range, show the latest.
        let month = months.contains(pickedMonth) ? pickedMonth : (months.first ?? "")
        let spend = Selectors.categorySpend(store.txns, store.activeLedgerId, month)
        let cats = spend
            .map { (id: $0.key, name: store.categoryName($0.key) ?? $0.key, spent: $0.value) }
            .filter { $0.spent > 0 }
            .sorted { $0.spent > $1.spent }
        let total = cats.reduce(0) { $0 + $1.spent }

        Card(title: "Breakdown") {
            if months.isEmpty {
                Text("No transactions yet").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Month", selection: Binding(get: { month }, set: { pickedMonth = $0 })) {
                    ForEach(months, id: \.self) { Text(monthLabel($0)).tag($0) }
                }
                .pickerStyle(.menu)
                LabeledContent("Total", value: store.displayMoneyBase(total))
                    .font(.subheadline).fontWeight(.medium)
                if cats.isEmpty {
                    Text("No spending in \(monthLabel(month))").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(cats.enumerated()), id: \.element.id) { i, c in
                            HStack(spacing: 12) {
                                Circle().fill(cardPalette[i % cardPalette.count]).frame(width: 10, height: 10)
                                Text(c.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text("\(total > 0 ? Int((c.spent / total * 100).rounded()) : 0)%")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(store.displayMoneyBase(c.spent)).font(.subheadline)
                            }
                            .padding(.vertical, 8)
                            if i < cats.count - 1 { Divider() }
                        }
                    }
                }
                Button {
                    exportCsv(month: month)
                } label: {
                    Label(month.isEmpty ? "Export CSV" : "Export \(monthLabel(month)) CSV", systemImage: "square.and.arrow.up")
                }
                .padding(.top, 4)
            }
        }
        .sheet(item: $exported) { f in ShareLink(item: f.url, preview: SharePreview("Transactions CSV")) }
    }

    private func exportCsv(month: String) {
        guard let csv = try? store.transactionsCsv(month: month.isEmpty ? nil : month) else { return }
        let suffix = [store.activeLedgerId, month].filter { !$0.isEmpty }.joined(separator: "-")
        let name = suffix.isEmpty ? "finch-transactions.csv" : "finch-transactions-\(suffix).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? csv.data(using: .utf8)?.write(to: url)) != nil else { return }
        exported = ExportedCsv(url: url)
    }
}

private struct ExportedCsv: Identifiable { let id = UUID(); let url: URL }

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
