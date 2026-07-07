import WidgetKit
import SwiftUI

/// Watch CP2 — the watch-face complication. Renders the WatchSnapshotPayload
/// the watch app persists to its App Group; refreshed by the app's
/// reloadAllTimelines() call on every received phone context.
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshotPayload?
}

struct ComplicationProvider: TimelineProvider {
    private func read() -> WatchSnapshotPayload? {
        guard let data = UserDefaults(suiteName: WatchStore.suite)?.data(forKey: WatchStore.key) else { return nil }
        return WatchSnapshotPayload.decode(data)
    }

    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // Hourly safety net; the real freshness path is the app's reload call.
        completion(Timeline(entries: [ComplicationEntry(date: .now, snapshot: read())],
                            policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var snap: WatchSnapshotPayload? { entry.snapshot }
    private var pct: Int { snap?.budgetUsedPct ?? 0 }
    private var nw: String { snap.map { $0.shortMoney($0.netWorth) } ?? "—" }
    private var wk: String { snap.map { $0.shortMoney($0.weeklySpent) } ?? "—" }
    private var dim: Bool { snap?.isStale ?? false }

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                gauge.widgetLabel { Text(nw) }
            case .accessoryInline:
                Text("finch · \(nw)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                    Text(nw).font(.headline).minimumScaleFactor(0.6).widgetAccentable()
                    Text("Budget \(pct)% · Wk \(wk)").font(.caption2).foregroundStyle(.secondary)
                }
            default: // .accessoryCircular
                gauge
            }
        }
        .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .containerBackground(.clear, for: .widget)
    }

    private var gauge: some View {
        Gauge(value: Double(pct), in: 0...100) {
            Text("Budget")
        } currentValueLabel: {
            Text(snap == nil ? "—" : "\(pct)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

@main
struct FinchWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FinchWatchComplication", provider: ComplicationProvider()) {
            ComplicationView(entry: $0)
        }
        .configurationDisplayName("finch")
        .description("Net worth and budget at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
