import AppIntents
import WidgetKit
import SwiftUI
import FinchCore

/// Phase 7 — the WidgetKit extension. Read-only; it renders the `WidgetSnapshot`
/// the app writes to the shared App Group container (no DB access in the
/// extension process). Net worth + a budget ring + this week's spend.
struct FinchEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct FinchProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinchEntry { FinchEntry(date: Date(), snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (FinchEntry) -> Void) {
        completion(FinchEntry(date: Date(), snapshot: AppGroup.readWidgetSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinchEntry>) -> Void) {
        let entry = FinchEntry(date: Date(), snapshot: AppGroup.readWidgetSnapshot())
        // Refresh hourly; the app also rewrites the snapshot after each backup.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct FinchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinchEntry

    private var pct: Int { entry.snapshot?.budgetUsedPct ?? 0 }
    private var nw: String { money(entry.snapshot?.netWorth, entry.snapshot?.currency) }
    private var wk: String { money(entry.snapshot?.weeklySpent, entry.snapshot?.currency) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(pct), in: 0...100) {
                Text("Budget")
            } currentValueLabel: {
                Text("\(pct)")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                Text(nw).font(.headline).minimumScaleFactor(0.6).widgetAccentable()
                Text("Budget \(pct)% · Wk \(wk)").font(.caption2).foregroundStyle(.secondary)
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text("finch · \(nw)")
                .containerBackground(.clear, for: .widget)
        default:
            systemLayout
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private var systemLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Net worth").font(.caption2).foregroundStyle(.secondary)
            Text(nw).font(.title3).fontWeight(.semibold).minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            HStack {
                Gauge(value: Double(pct), in: 0...100) {
                    Text("Budget")
                } currentValueLabel: {
                    Text("\(pct)%").font(.caption2)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .scaleEffect(0.8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("This week").font(.caption2).foregroundStyle(.secondary)
                    Text(wk).font(.caption).fontWeight(.medium)
                }
            }
        }
        .padding()
    }

    private func money(_ amount: Double?, _ currency: String?) -> String {
        guard let amount else { return "—" }
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency ?? "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }
}

struct FinchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FinchOverview", provider: FinchProvider()) { entry in
            FinchWidgetView(entry: entry)
        }
        .configurationDisplayName("finch overview")
        .description("Net worth, budget usage, and this week's spending.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AccountEntry: TimelineEntry {
    let date: Date
    let item: AccountSnapshotItem?
}

struct AccountProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AccountEntry { AccountEntry(date: Date(), item: nil) }
    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> AccountEntry { entry(configuration) }
    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<AccountEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }
    private func entry(_ c: SelectAccountIntent) -> AccountEntry {
        let snap = AppGroup.readWidgetSnapshot()
        let item = snap?.accounts?.first { $0.id == c.account?.id } ?? snap?.accounts?.first
        return AccountEntry(date: Date(), item: item)
    }
}

struct AccountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AccountEntry
    var body: some View {
        if let item = entry.item {
            let amount = Money.format(item.balance, currency: item.currency)
            switch family {
            case .accessoryInline:
                Text("\(item.name) · \(amount)").containerBackground(.clear, for: .widget)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.caption2).foregroundStyle(.secondary)
                    Text(amount).font(.headline).minimumScaleFactor(0.6).widgetAccentable()
                }.containerBackground(.clear, for: .widget)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.caption).foregroundStyle(.secondary)
                    Text(amount).font(.title3).fontWeight(.semibold).minimumScaleFactor(0.6)
                }.padding().containerBackground(.fill.tertiary, for: .widget)
            }
        } else {
            Text("Pick an account").font(.caption).foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct AccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FinchAccount", intent: SelectAccountIntent.self, provider: AccountProvider()) { entry in
            AccountWidgetView(entry: entry)
        }
        .configurationDisplayName("finch account")
        .description("A chosen account's balance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct BudgetEntry: TimelineEntry {
    let date: Date
    let item: BudgetSnapshotItem?
}

struct BudgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry { BudgetEntry(date: Date(), item: nil) }
    func snapshot(for configuration: SelectBudgetIntent, in context: Context) async -> BudgetEntry { entry(configuration) }
    func timeline(for configuration: SelectBudgetIntent, in context: Context) async -> Timeline<BudgetEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }
    private func entry(_ c: SelectBudgetIntent) -> BudgetEntry {
        let snap = AppGroup.readWidgetSnapshot()
        let item = snap?.budgets?.first { $0.id == c.budget?.id } ?? snap?.budgets?.first
        return BudgetEntry(date: Date(), item: item)
    }
}

struct BudgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry
    var body: some View {
        if let item = entry.item {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(item.usedPct), in: 0...100) { Text("Budget") } currentValueLabel: { Text("\(item.usedPct)") }
                    .gaugeStyle(.accessoryCircular)
                    .containerBackground(.clear, for: .widget)
            default:
                VStack(spacing: 6) {
                    Text(item.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Gauge(value: Double(item.usedPct), in: 0...100) { Text("Budget") } currentValueLabel: { Text("\(item.usedPct)%") }
                        .gaugeStyle(.accessoryCircularCapacity)
                }.padding().containerBackground(.fill.tertiary, for: .widget)
            }
        } else {
            Text("Pick a budget").font(.caption).foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FinchBudget", intent: SelectBudgetIntent.self, provider: BudgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("finch budget")
        .description("A chosen budget's usage.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main
struct FinchWidgetBundle: WidgetBundle {
    var body: some Widget { FinchWidget(); AccountWidget(); BudgetWidget() }
}
