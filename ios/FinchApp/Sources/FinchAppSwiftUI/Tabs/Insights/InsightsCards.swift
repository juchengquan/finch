import SwiftUI
import FinchCore

/// Shared card chrome.
struct Card<Content: View>: View {
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

struct InsightsCard: View {
    @EnvironmentObject private var store: FinchStore
    /// Collapse state, persisted per-device. Collapsed shows the single top insight
    /// as a teaser; expanded reveals all. Chevron-disclosure header (Insights redesign).
    @AppStorage("finch.insights.highlightsExpanded") private var expanded = false

    var body: some View {
        let ctx = InsightContext(
            txns: store.txns, accounts: store.accounts, budgets: store.budgets,
            categories: store.pickableCategories, ledgerId: store.activeLedgerId,
            month: String(store.today.prefix(7)), today: store.today)
        let insights = Selectors.generateInsights(ctx, fmt: store.displayMoneyBase)
        // Custom card chrome (matches `Card`) — the header is a disclosure control,
        // so we can't reuse `Card(title:)`.
        return VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("Highlights").font(.headline).foregroundStyle(.primary)
                    if !expanded && insights.count > 1 {
                        Text("\(insights.count)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    if insights.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(insights.count <= 1)

            if insights.isEmpty {
                Text("Add a few transactions to see insights.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if expanded {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, ins in row(ins) }
            } else if let first = insights.first {
                row(first)   // teaser: the top insight stays visible while collapsed
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
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
        case "calendar": return "calendar"; case "tag": return "tag"
        default: return "sparkles"
        }
    }
}

let cardPalette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]

struct MonthlySpendingCard: View {
    @EnvironmentObject private var store: FinchStore
    var months = 6
    var body: some View {
        let endMonth = String(store.today.prefix(7))
        let pts = Selectors.monthlySpending(store.txns, store.activeLedgerId, endMonth, months)
        Card(title: "Monthly spending") {
            BarChart(data: pts.map { BarChart.DataPoint(label: $0.m, value: $0.v, color: .blue) },
                     xLabel: "Month", yLabel: "Spent", format: store.displayMoneyBase)
                .frame(height: 180)
        }
    }
}

struct NetWorthCard: View {
    @EnvironmentObject private var store: FinchStore
    var months = 6
    var body: some View {
        let endMonth = String(store.today.prefix(7))
        let pts = Selectors.netWorthByMonth(store.txns, store.accounts, store.activeLedgerId, endMonth, months)
        Card(title: "Net worth") {
            LineChart(data: pts.map { LineChart.DataPoint(x: $0.m, y: $0.v) },
                      xLabel: "Month", yLabel: "Net worth", format: store.displayMoneyBase)
                .frame(height: 180)
        }
    }
}

struct CategoryBreakdownCard: View {
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
                Donut(data: data, centerLabel: "This month", format: store.displayMoneyBase)
                    .frame(height: 200)
            }
        }
    }
}

/// Where this month's expense money went, by merchant — a StackedBar of the
/// top-5 shares + a ranked row per merchant.
struct TopMerchantsCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let rows = Selectors.topMerchants(store.txns, store.activeLedgerId, String(store.today.prefix(7)))
        Card(title: "Top merchants") {
            if rows.isEmpty {
                Text("No spending this month").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    StackedBar(slices: Array(rows.enumerated()).map { i, r in
                        StackedBar.Slice(value: r.total, color: cardPalette[i % cardPalette.count])
                    })
                    .padding(.bottom, 4)
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        HStack {
                            Circle().fill(cardPalette[i % cardPalette.count]).frame(width: 8, height: 8)
                            Text(r.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text(store.displayMoneyBase(r.total)).font(.caption).fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }
}

struct ForecastCard: View {
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
func monthLabel(_ ym: String) -> String {
    guard ym.count >= 7, let mi = Int(ym.suffix(2)), (1...12).contains(mi) else { return ym }
    return "\(monthNames[mi - 1]) \(ym.prefix(4))"
}

/// The former Reports page, ported as the Insights "Breakdown" view: a month
/// picker (months with data, newest first), the per-category spend list for
/// that month, and a transactions-CSV export scoped to the month.
struct BreakdownView: View {
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
                HStack(spacing: 16) {
                    Button {
                        exportCsv(month: month)
                    } label: {
                        Label(month.isEmpty ? "Export CSV" : "Export \(monthLabel(month)) CSV", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        exportPdf(month: month, cats: cats, total: total)
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                }
                .padding(.top, 4)
            }
        }
        .sheet(item: $exported) { f in ShareLink(item: f.url, preview: SharePreview(f.url.lastPathComponent)) }
    }

    /// One-page print-styled report of the picked month (see ReportPdf.swift).
    private func exportPdf(month: String, cats: [(id: String, name: String, spent: Double)], total: Double) {
        let flow = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, month, 1).last
        let income = flow?.inc ?? 0
        let spent = flow?.exp ?? 0
        let model = MonthlyReportModel(
            ledgerName: store.ledgers.first { $0.id == store.activeLedgerId }?.name ?? store.activeLedgerId,
            monthLabel: monthLabel(month),
            income: store.displayMoneyBase(income),
            spent: store.displayMoneyBase(spent),
            net: store.displayMoneyBase(income - spent),
            categories: cats.map {
                .init(name: $0.name, amount: store.displayMoneyBase($0.spent),
                      pct: total > 0 ? Int(($0.spent / total * 100).rounded()) : 0)
            },
            merchants: Selectors.topMerchants(store.txns, store.activeLedgerId, month).map {
                .init(name: $0.name, amount: store.displayMoneyBase($0.total))
            },
            generatedAt: Date.now.formatted(date: .abbreviated, time: .shortened))
        guard let data = ReportPdf.render(MonthlyReportView(model: model)) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finch-report-\(store.activeLedgerId)-\(month).pdf")
        guard (try? data.write(to: url)) != nil else { return }
        exported = ExportedCsv(url: url)
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

struct ExportedCsv: Identifiable { let id = UUID(); let url: URL }

// MARK: - Tier 2 parity cards

/// Monthly income vs expense (net cashflow line), range-aware.
struct CashflowCard: View {
    @EnvironmentObject private var store: FinchStore
    var months = 6
    var body: some View {
        let pts = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, String(store.today.prefix(7)), months)
        Card(title: "Cashflow (net)") {
            if pts.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            } else {
                LineChart(data: pts.map { LineChart.DataPoint(x: $0.m, y: $0.inc - $0.exp) },
                          xLabel: "Month", yLabel: "Net", format: store.displayMoneyBase)
                    .frame(height: 160)
            }
        }
    }
}

/// This month's savings rate — (income − expense) ÷ income — as a Ring.
/// Inline math from `monthlyCashflow`; handles no-income and overspent (negative).
struct SavingsRateCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let pt = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, String(store.today.prefix(7)), 1).last
        let inc = pt?.inc ?? 0
        let exp = pt?.exp ?? 0
        let rate: Double? = inc > 0 ? (inc - exp) / inc : nil
        Card(title: "Savings rate") {
            if let rate {
                let pct = Int((rate * 100).rounded())
                HStack(spacing: 16) {
                    Ring(value: Swift.max(0, rate * 100), max: 100,
                         color: rate >= 0 ? .green : .orange) {
                        Text("\(pct)%").font(.caption).fontWeight(.semibold)
                    }
                    Text(rate >= 0 ? "of income saved this month"
                                   : "spent more than earned this month")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No income this month").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// What-if sliders — interactive category-cut hypotheticals over a real-history
/// baseline (web parity: #411). Drag a category's slider to a % cut and see the
/// monthly/annual savings plus the effect on average monthly net. Pure client
/// math — cuts are @State only; nothing persists.
struct WhatIfCard: View {
    @EnvironmentObject private var store: FinchStore
    @State private var cuts: [String: Double] = [:]

    var body: some View {
        let baseline = Selectors.whatIfBaseline(store.txns, store.activeLedgerId, String(store.today.prefix(7)))
        Card(title: "What if…") {
            if let b = baseline {
                content(b)
            } else {
                Text("Not enough spending history yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func content(_ b: Selectors.WhatIfBaseline) -> some View {
        let monthlySave = b.categories.reduce(0.0) { $0 + $1.avgMonthly * (cuts[$1.categoryId] ?? 0) / 100 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Based on your last \(b.months.count) month\(b.months.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if monthlySave > 0 {
                    Button("Reset") { cuts = [:] }.font(.caption)
                }
            }
            ForEach(b.categories, id: \.categoryId) { c in row(c) }
            if monthlySave > 0 {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.displayMoneyBase(monthlySave * 12)).font(.title3).fontWeight(.semibold)
                    Text("per year").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.displayMoneyBase(monthlySave))/mo").font(.caption).foregroundStyle(.secondary)
                }
                // Web parity: the net line only renders when the window saw income
                // (what-if-card.tsx gates on avgIncome > 0) — a zero-income window
                // would otherwise show a misleading all-spend "net".
                if b.avgIncome > 0 {
                    let netBefore = b.avgIncome - b.avgSpend
                    Text("Net: \(store.displayMoneyBase(netBefore)) → \(store.displayMoneyBase(netBefore + monthlySave))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Drag a slider to try a cut.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func row(_ c: Selectors.WhatIfBaseline.Category) -> some View {
        let pct = cuts[c.categoryId] ?? 0
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(store.categoryName(c.categoryId) ?? c.categoryId)
                Spacer()
                Text("avg \(store.displayMoneyBase(c.avgMonthly))/mo").font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { cuts[c.categoryId] ?? 0 },
                                  set: { cuts[c.categoryId] = $0 }),
                   in: 0...100, step: 5)
                .accessibilityLabel("Cut \(store.categoryName(c.categoryId) ?? c.categoryId)")
                .accessibilityValue("\(Int(pct)) percent")
            if pct > 0 {
                Text("cut \(Int(pct))% → saves ~\(store.displayMoneyBase(c.avgMonthly * pct / 100))/mo")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Biggest month-over-month category movers.
struct CategoryDeltasCard: View {
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
struct WeeklyDigestCard: View {
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
struct IncomeSankeyCard: View {
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
struct SpendingHeatmapCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let days = Selectors.dailySpending(store.txns, store.activeLedgerId, store.today, 12 * 7)
        Card(title: "Daily spending (12 weeks)") {
            if days.allSatisfy({ $0.value == 0 }) {
                Text("No spending").font(.caption).foregroundStyle(.secondary)
            } else {
                CalendarHeatmap(values: days.map { ($0.date, $0.value) },
                                format: { store.displayMoneyBase($0) })
            }
        }
    }
}

/// Net worth split by account type.
struct NetWorthByTypeCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let rows = Selectors.netWorthByAccountType(store.accounts, store.activeLedgerId) { store.toBase($0, from: $1) }
            .filter { $0.balance != 0 }
        let assets = rows.filter { $0.balance > 0 }
        Card(title: "Net worth by type") {
            if rows.isEmpty {
                Text("No accounts").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    if !assets.isEmpty {
                        StackedBar(slices: assets.map {
                            StackedBar.Slice(value: $0.balance, color: AccountTypeColor.color(for: $0.type))
                        })
                        .padding(.bottom, 4)
                    }
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

// MARK: - Card registry (Insights customizable dashboard, Task 1)

/// One dashboard card in the catalog: a stable id, a title for the Customize
/// list, whether it consumes the 3M/6M/1Y range, and a builder.
struct InsightsCardEntry: Identifiable {
    let id: String
    let title: String
    let consumesRange: Bool
    let make: (_ rangeMonths: Int) -> AnyView
}

/// The single source of truth for the dashboard's cards, in default order.
enum InsightsCatalog {
    static let all: [InsightsCardEntry] = [
        .init(id: "tips",              title: "Highlights",         consumesRange: false, make: { _ in AnyView(InsightsCard()) }),
        .init(id: "monthlySpending",   title: "Monthly spending",   consumesRange: true,  make: { AnyView(MonthlySpendingCard(months: $0)) }),
        .init(id: "netWorth",          title: "Net worth",          consumesRange: true,  make: { AnyView(NetWorthCard(months: $0)) }),
        .init(id: "cashflow",          title: "Cashflow",           consumesRange: true,  make: { AnyView(CashflowCard(months: $0)) }),
        .init(id: "savingsRate",       title: "Savings rate",       consumesRange: false, make: { _ in AnyView(SavingsRateCard()) }),
        .init(id: "whatIf",            title: "What-if",            consumesRange: false, make: { _ in AnyView(WhatIfCard()) }),
        .init(id: "categoryDeltas",    title: "Category changes",   consumesRange: false, make: { _ in AnyView(CategoryDeltasCard()) }),
        .init(id: "weeklyDigest",      title: "Weekly digest",      consumesRange: false, make: { _ in AnyView(WeeklyDigestCard()) }),
        .init(id: "incomeSankey",      title: "Income flow",        consumesRange: false, make: { _ in AnyView(IncomeSankeyCard()) }),
        .init(id: "spendingHeatmap",   title: "Spending heatmap",   consumesRange: false, make: { _ in AnyView(SpendingHeatmapCard()) }),
        .init(id: "netWorthByType",    title: "Net worth by type",  consumesRange: false, make: { _ in AnyView(NetWorthByTypeCard()) }),
        .init(id: "categoryBreakdown", title: "Category breakdown", consumesRange: false, make: { _ in AnyView(CategoryBreakdownCard()) }),
        .init(id: "topMerchants",      title: "Top merchants",      consumesRange: false, make: { _ in AnyView(TopMerchantsCard()) }),
        .init(id: "forecast",          title: "Forecast",           consumesRange: false, make: { _ in AnyView(ForecastCard()) }),
    ]
    static func entry(_ id: String) -> InsightsCardEntry? { all.first { $0.id == id } }
}
