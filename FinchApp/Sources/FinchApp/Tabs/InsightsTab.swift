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
                                CategoryDeltasCard()
                                WeeklyDigestCard()
                                IncomeSankeyCard()
                                SpendingHeatmapCard()
                                NetWorthByTypeCard()
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
            .settingsPush()
            #if os(iOS)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { SettingsBarButton() }   // .topBarTrailing is iOS-only; gear is compact-only (macOS uses the sidebar)
                #endif
            }
            #endif
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

private struct InsightsCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let ctx = InsightContext(
            txns: store.txns, accounts: store.accounts, budgets: store.budgets,
            categories: store.pickableCategories, ledgerId: store.activeLedgerId,
            month: String(store.today.prefix(7)), today: store.today)
        let insights = Selectors.generateInsights(ctx, fmt: store.displayMoneyBase)
        return Card(title: "Insights") {
            if insights.isEmpty {
                Text("Add a few transactions to see insights.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(insights.enumerated()), id: \.offset) { _, ins in row(ins) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ ins: Insight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(ins.icon))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(color(ins.tone).opacity(0.15), in: Circle())
                .foregroundStyle(color(ins.tone))
            VStack(alignment: .leading, spacing: 2) {
                Text(ins.title).font(.subheadline.weight(.medium))
                Text(ins.body).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func color(_ t: Insight.Tone) -> Color {
        switch t { case .pos: return .green; case .warn: return .orange; case .neut: return .blue }
    }
    private func symbol(_ icon: String) -> String {
        switch icon {
        case "arrowUp": return "arrow.up"; case "arrowDown": return "arrow.down"
        case "doc": return "doc.text"; case "fork": return "fork.knife"; case "check": return "checkmark"
        default: return "sparkles"
        }
    }
}

private let cardPalette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]

private struct MonthlySpendingCard: View {
    @EnvironmentObject private var store: FinchStore
    var months = 6
    var body: some View {
        let endMonth = String(store.today.prefix(7))
        let pts = Selectors.monthlySpending(store.txns, store.activeLedgerId, endMonth, months)
        Card(title: "Monthly spending") {
            BarChart(data: pts.map { BarChart.DataPoint(label: $0.m, value: $0.v, color: .blue) },
                     xLabel: "Month", yLabel: "Spent")
                .frame(height: 180)
        }
    }
}

private struct NetWorthCard: View {
    @EnvironmentObject private var store: FinchStore
    var months = 6
    var body: some View {
        let endMonth = String(store.today.prefix(7))
        let pts = Selectors.netWorthByMonth(store.txns, store.accounts, store.activeLedgerId, endMonth, months)
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
                            // recentExpenses returns a positive magnitude; render
                            // as a spend. `-abs` is robust to the sign convention.
                            Text(Money.format(-abs(r.amount), currency: r.currency)).fontWeight(.medium)
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
                        Text(Selectors.holdingValue(h).map { store.displayMoney($0, from: h.currency) } ?? "—")
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }
}

// MARK: - Tier 2 parity cards

/// Monthly income vs expense (net cashflow line), range-aware.
private struct CashflowCard: View {
    @EnvironmentObject private var store: FinchStore
    var months = 6
    var body: some View {
        let pts = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, String(store.today.prefix(7)), months)
        Card(title: "Cashflow (net)") {
            if pts.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            } else {
                LineChart(data: pts.map { LineChart.DataPoint(x: $0.m, y: $0.inc - $0.exp) },
                          xLabel: "Month", yLabel: "Net")
                    .frame(height: 160)
            }
        }
    }
}

/// Biggest month-over-month category movers.
private struct CategoryDeltasCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let refs = store.pickableCategories.map { CategoryRef(id: $0.id, name: $0.name) }
        let deltas = Selectors.topCategoryDeltas(store.txns, store.activeLedgerId, String(store.today.prefix(7)), refs, 5)
        Card(title: "Month-over-month") {
            if deltas.isEmpty {
                Text("Not enough history").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(deltas.enumerated()), id: \.offset) { _, d in
                        HStack {
                            Text(d.name).lineLimit(1)
                            Spacer()
                            Text(store.displayMoneyBase(d.b)).font(.caption).foregroundStyle(.secondary)
                            Text("\(d.d > 0 ? "+" : "")\(d.d)%")
                                .font(.caption.monospaced())
                                .foregroundStyle(d.d > 0 ? .red : .green)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

/// This week's recap: spent / income / net vs prior + 12-week average.
private struct WeeklyDigestCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        Card(title: "This week") {
            if let d = Selectors.weeklyDigest(store.txns, store.activeLedgerId, store.today) {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Spent", value: store.displayMoneyBase(d.spent))
                    LabeledContent("Income", value: store.displayMoneyBase(d.income))
                    LabeledContent("Net", value: store.displayMoneyBase(d.net))
                    if let vs = d.vsAvgPct {
                        Text("\(vs > 0 ? "+" : "")\(Int(vs))% vs \(d.avgWeeks)-week average")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No activity this week").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Income → categories proportional flow (simplified Sankey).
private struct IncomeSankeyCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let cats = store.pickableCategories.map { ColoredCategory(id: $0.id, name: $0.name, color: nil) }
        let flow = Selectors.incomeCategoryFlow(store.txns, cats, store.activeLedgerId, String(store.today.prefix(7)))
        Card(title: "Where income goes") {
            if flow.income <= 0 {
                Text("No income this month").font(.caption).foregroundStyle(.secondary)
            } else {
                Sankey(total: flow.income, segments: segments(flow))
            }
        }
    }

    private func segments(_ flow: IncomeFlow) -> [Sankey.Segment] {
        var segs = flow.categories.enumerated().map { i, c in
            Sankey.Segment(id: c.id, label: c.name, value: c.spent, color: cardPalette[i % cardPalette.count])
        }
        if flow.saved > 0 { segs.append(Sankey.Segment(id: "__saved", label: "Saved", value: flow.saved, color: .gray)) }
        return segs
    }
}

/// 12-week daily-spend intensity grid.
private struct SpendingHeatmapCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let days = Selectors.dailySpending(store.txns, store.activeLedgerId, store.today, 12 * 7)
        Card(title: "Daily spending (12 weeks)") {
            if days.allSatisfy({ $0.value == 0 }) {
                Text("No spending").font(.caption).foregroundStyle(.secondary)
            } else {
                CalendarHeatmap(values: days.map { ($0.date, $0.value) })
            }
        }
    }
}

/// Net worth split by account type.
private struct NetWorthByTypeCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let rows = Selectors.netWorthByAccountType(store.accounts, store.activeLedgerId) { store.toBase($0, from: $1) }
            .filter { $0.balance != 0 }
        Card(title: "Net worth by type") {
            if rows.isEmpty {
                Text("No accounts").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(AccountSheetTypeLabel.label(r.type))
                            Spacer()
                            Text(store.displayMoneyBase(r.balance)).fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }
}
