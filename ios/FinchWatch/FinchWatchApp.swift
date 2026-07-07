import SwiftUI
import WatchConnectivity
import WidgetKit

/// Watch sub-project CP1 — the standalone watchOS glance. App Groups don't span
/// devices, so the watch can't read the phone's container; instead it receives the
/// phone's snapshot over WCSession (see PhoneWatchLink), persists it to its OWN App
/// Group, and renders it. Uses the shared `WatchSnapshotPayload` wire format.
final class WatchSnapshotStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: WatchSnapshotPayload?
    private let suite = UserDefaults(suiteName: WatchStore.suite)
    private let key = WatchStore.key

    override init() {
        super.init()
        if let data = suite?.data(forKey: key) { snapshot = WatchSnapshotPayload.decode(data) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data,
              let incoming = WatchSnapshotPayload.decode(data) else { return }
        Task { @MainActor in
            if let cur = self.snapshot, incoming.generatedAt < cur.generatedAt { return }  // ignore stale
            self.suite?.set(data, forKey: self.key)
            self.snapshot = incoming
            WidgetCenter.shared.reloadAllTimelines()   // CP2: refresh the complication on every push
        }
    }
}

struct GlanceView: View {
    @ObservedObject var store: WatchSnapshotStore

    var body: some View {
        ScrollView {
            if let snap = store.snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                    Text(money(snap.netWorth, snap.currency)).font(.title3).fontWeight(.semibold).minimumScaleFactor(0.6)
                    Gauge(value: Double(snap.budgetUsedPct), in: 0...100) {
                        Text("Budget")
                    } currentValueLabel: {
                        Text("\(snap.budgetUsedPct)%")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    HStack {
                        Text("This week").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(money(snap.weeklySpent, snap.currency)).font(.caption)
                    }
                }
                .padding()
            } else {
                VStack(spacing: 6) {
                    Text("No data yet").font(.headline)
                    Text("Open finch on your iPhone").font(.caption2)
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }

    private func money(_ amount: Double, _ currency: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }
}

@main
struct FinchWatchApp: App {
    @StateObject private var store = WatchSnapshotStore()
    var body: some Scene {
        WindowGroup { GlanceView(store: store) }
    }
}
