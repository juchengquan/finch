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

@main
struct FinchWidgetBundle: WidgetBundle {
    var body: some Widget { FinchWidget() }
}
