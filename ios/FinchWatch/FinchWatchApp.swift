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

    /// CP3 — queue a quick-add to the phone (transferUserInfo survives
    /// unreachability). Stamps the tap time so a queued add books on the day
    /// it was tapped. Returns whether it was queued.
    func sendQuickAdd(_ item: WatchQuickAddItem) -> Bool {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return false }
        var req = WatchQuickAddRequest(id: UUID().uuidString, item: item)
        req.createdAt = Date()
        guard let data = req.encoded() else { return false }
        WCSession.default.transferUserInfo(["quickAdd": data])
        return true
    }
}

struct GlanceView: View {
    @ObservedObject var store: WatchSnapshotStore
    @State private var sentKeys: Set<String> = []   // CP3: rows already queued this session
    @State private var showingCompose = false       // CP3 composer sheet

    var body: some View {
        NavigationStack {
            glanceBody
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingCompose = true } label: { Image(systemName: "plus") }
                            .disabled(store.snapshot?.quickAdd == nil)   // no catalog yet → "Open finch on your iPhone"
                            .accessibilityLabel("Add expense")
                    }
                }
                .sheet(isPresented: $showingCompose) {
                    if let snap = store.snapshot, let catalog = snap.quickAdd {
                        QuickAddView(catalog: catalog, currency: snap.currency, store: store)
                    }
                }
        }
    }

    private var glanceBody: some View {
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
                    if let recents = snap.recents, !recents.isEmpty {
                        Divider().padding(.vertical, 2)
                        Text("Quick add").font(.caption2).foregroundStyle(.secondary)
                        ForEach(Array(recents.enumerated()), id: \.offset) { _, item in
                            quickAddRow(item)
                        }
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

    /// CP3 — one tappable template row. The checkmark means "queued to the
    /// phone" (transferUserInfo delivers when reachable); the next snapshot
    /// push updates the figures above as the real confirmation.
    @ViewBuilder private func quickAddRow(_ item: WatchQuickAddItem) -> some View {
        let key = "\(item.merchant)|\(item.amount)|\(item.accountId)"
        Button {
            if store.sendQuickAdd(item) { sentKeys.insert(key) }
        } label: {
            HStack {
                Text(item.merchant).font(.caption).lineLimit(1)
                Spacer()
                if sentKeys.contains(key) {
                    Image(systemName: "checkmark").font(.caption2)
                } else {
                    Text(WatchMoney.short(item.amount, currency: item.currency))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func money(_ amount: Double, _ currency: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }
}

/// CP3 composer (spec §4) — amount via the digital crown + quick bumps,
/// category chips from the snapshot-borne catalog, Add queues the request.
/// Three taps for the common case; "Added" means queued (transferUserInfo
/// delivers when the phone next runs), the next snapshot updates the figures.
struct QuickAddView: View {
    let catalog: WatchQuickAddCatalog
    let currency: String
    @ObservedObject var store: WatchSnapshotStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double = 0
    @State private var categoryId = ""
    @State private var sent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if sent {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                    Text("Added — syncs to iPhone").font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(WatchMoney.short(amount, currency: currency))
                        .font(.title2).fontWeight(.semibold)
                        .focusable()
                        .digitalCrownRotation($amount, from: 0, through: 500, by: 0.5,
                                              sensitivity: .medium, isContinuous: false,
                                              isHapticFeedbackEnabled: true)
                        .onLongPressGesture { amount = 0 }
                    HStack(spacing: 4) {
                        bump(1); bump(5); bump(10)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(catalog.categories, id: \.id) { c in
                                Button(c.name) { categoryId = c.id }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                    .tint(categoryId == c.id ? .green : .gray)
                            }
                        }
                    }
                    Text(catalog.accountName).font(.caption2).foregroundStyle(.secondary)
                    Button("Add") { send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(amount <= 0)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear { if categoryId.isEmpty { categoryId = catalog.categories.first?.id ?? "" } }
    }

    private func bump(_ v: Double) -> some View {
        Button("+\(Int(v))") { amount = min(500, amount + v) }.font(.caption2)
    }

    private func send() {
        let item = WatchQuickAddItem(
            merchant: catalog.categories.first { $0.id == categoryId }?.name ?? "Expense",
            amount: amount, currency: currency,
            ledgerId: catalog.ledgerId, accountId: catalog.accountId,
            categoryId: categoryId.isEmpty ? nil : categoryId)
        guard store.sendQuickAdd(item) else { return }
        sent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}

@main
struct FinchWatchApp: App {
    @StateObject private var store = WatchSnapshotStore()
    var body: some Scene {
        WindowGroup { GlanceView(store: store) }
    }
}
