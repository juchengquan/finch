import SwiftUI

/// Phase 7 — the Apple Watch glance. A self-contained watchOS app (watchOS has
/// no DB access and a limited SwiftUI surface, so it does NOT share the iOS
/// views): it reads the `WidgetSnapshot` the phone writes to the shared App Group
/// and shows net worth + budget usage + this-week spend. A small local copy of
/// the snapshot type avoids pulling FinchCore/GRDB onto the watch.

struct WatchSnapshot: Codable {
    var netWorth: Double
    var currency: String
    var budgetUsedPct: Int
    var weeklySpent: Double
    var generatedAt: String

    static func load() -> WatchSnapshot? {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.juchengquan.finch")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = base?.appendingPathComponent("widget_snapshot.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}

struct GlanceView: View {
    @State private var snap: WatchSnapshot? = WatchSnapshot.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                Text(money(snap?.netWorth, snap?.currency)).font(.title3).fontWeight(.semibold).minimumScaleFactor(0.6)
                Gauge(value: Double(snap?.budgetUsedPct ?? 0), in: 0...100) {
                    Text("Budget")
                } currentValueLabel: {
                    Text("\(snap?.budgetUsedPct ?? 0)%")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                HStack {
                    Text("This week").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(money(snap?.weeklySpent, snap?.currency)).font(.caption)
                }
            }
            .padding()
        }
        .onAppear { snap = WatchSnapshot.load() }
    }

    private func money(_ amount: Double?, _ currency: String?) -> String {
        guard let amount else { return "—" }
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency ?? "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }
}

@main
struct FinchWatchApp: App {
    var body: some Scene {
        WindowGroup { GlanceView() }
    }
}
