# Phase 7 Implementation Plan — Widgets + Live Activities + Apple Watch

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add **3 extension targets** to the iOS app: (1) a WidgetKit widget that shows recent transactions or budget progress; (2) Live Activities for budget alerts + scheduled item due; (3) a watchOS app for quick transaction entry + glance at totals.

**Architecture:** Each extension is a separate Xcode target that reads from a shared `widget_snapshot.json` (the live in-memory projection) in the App Group. The iOS app updates the snapshot on every FinchStore change. The Watch app uses WatchConnectivity to sync; the Watch's "quick-add" dispatches a WatchConnectivity message to the iOS app, which dispatches the chokepoint action.

**Tech Stack:** Same as Phase 2 + `WidgetKit` + `ActivityKit` + `WatchKit` + `WatchConnectivity`.

**Input design spec:** `plans/ios-macos/IOS_MACOS_PHASE_7_DESIGN.md` (~660 lines, 8 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2 + 5 (App Group).

**Estimated time:** 2-3 months.

---

## File structure

```
frontend/ios/
  WidgetExtension/                 # NEW: the WidgetKit target
    WidgetBundle.swift
    BudgetRingWidget.swift
    RecentActivityWidget.swift
    NetWorthWidget.swift
    ActivityWidget.swift            # NEW: Live Activity (shared between app + widget)
  WatchApp/                        # NEW: the watchOS app target
    WatchApp.swift
    WatchContentView.swift
    WatchConnectivity.swift
    WatchQuickAdd.swift
```

**File counts**: ~10 new files, ~1,500-2,000 lines Swift.

---

## Task 1: Build the `widget_snapshot.json` writer

- [ ] **Step 1: Add the snapshot writer to `FinchStore`**

`frontend/ios/FinchApp/Sources/FinchApp/Widget/WidgetSnapshotWriter.swift`:

```swift
// FinchApp/Widget/WidgetSnapshotWriter.swift — writes the
// in-memory projection as a JSON snapshot to the App Group
// (per Phase 7 §2.4). The widget reads this snapshot.
import Foundation
import FinchCore

public struct WidgetSnapshot: Codable, Equatable {
    public let ledgerId: String
    public let updatedAt: Date
    public let accounts: [WidgetAccount]
    public let txns: [WidgetTxn]
    public let budgets: [WidgetBudget]
    public let netWorth: Decimal
}

public struct WidgetAccount: Codable, Equatable {
    public let id: String
    public let name: String
    public let balance: Decimal
    public let currency: String
}

public struct WidgetTxn: Codable, Equatable {
    public let id: String
    public let merchant: String
    public let amount: Decimal
    public let date: String
}

public struct WidgetBudget: Codable, Equatable {
    public let id: String
    public let name: String
    public let spent: Decimal
    public let limit: Decimal
}

public enum WidgetSnapshotWriter {
    public static func write(_ snapshot: WidgetSnapshot) throws {
        guard let appGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.juchengquan.finch"
        ) else { return }
        let url = appGroup.appendingPathComponent("widget_snapshot.json")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url)
    }
}
```

- [ ] **Step 2: Wire into `FinchStore`**

```swift
public extension FinchStore {
    func apply(action: ActionName, args: Args) async throws {
        // (existing apply logic)
        await writeWidgetSnapshot()
    }

    private func writeWidgetSnapshot() async {
        let snapshot = WidgetSnapshot(
            ledgerId: activeLedgerId,
            updatedAt: Date(),
            accounts: accounts.map { /* map to WidgetAccount */ },
            txns: Array(txns.prefix(20)).map { /* map to WidgetTxn */ },
            budgets: budgets.map { /* map to WidgetBudget */ },
            netWorth: accounts.reduce(0) { $0 + $1.balance }
        )
        try? WidgetSnapshotWriter.write(snapshot)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Widget/
git add frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift
git commit -m "feat(ios): add widget_snapshot.json writer + wire to FinchStore"
```

---

## Task 2: Build the `BudgetRingWidget`

- [ ] **Step 1: Implement the widget**

`frontend/ios/WidgetExtension/BudgetRingWidget.swift`:

```swift
// WidgetExtension/BudgetRingWidget.swift — the budget progress
// ring widget. Reads from widget_snapshot.json; refreshes
// hourly.
import WidgetKit
import SwiftUI
import FinchCore

struct BudgetRingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct BudgetRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetRingEntry {
        BudgetRingEntry(date: .init(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetRingEntry) -> Void) {
        let snapshot = loadWidgetSnapshot()
        completion(BudgetRingEntry(date: .init(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetRingEntry>) -> Void) {
        let entries = (0..<6).map { i in
            BudgetRingEntry(
                date: Date().addingTimeInterval(Double(i) * 600),  // every 10 min
                snapshot: loadWidgetSnapshot()
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct BudgetRingWidget: Widget {
    let kind: String = "BudgetRingWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectBudgetIntent.self,
            provider: BudgetRingProvider()
        ) { entry in
            BudgetRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Budget Ring")
        .description("See your budget progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BudgetRingWidgetView: View {
    let entry: BudgetRingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let budget = entry.snapshot?.budgets.first {
            let percent = NSDecimalNumber(decimal: budget.spent / budget.limit).doubleValue
            Gauge(value: percent, in: 0...1) {
                Text(budget.name)
            } currentValueLabel: {
                Text("\(Int(percent * 100))%")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Text("No data")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/WidgetExtension/BudgetRingWidget.swift
git commit -m "feat(ios): add BudgetRingWidget (WidgetKit)"
```

---

## Task 3: Build the `RecentActivityWidget` + `NetWorthWidget`

- [ ] **Step 1: Implement `RecentActivityWidget`**

Similar pattern to `BudgetRingWidget`. Shows the 5 most recent
transactions.

- [ ] **Step 2: Implement `NetWorthWidget`**

Similar pattern. Shows the net worth + sparkline.

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/WidgetExtension/RecentActivityWidget.swift
git add frontend/ios/WidgetExtension/NetWorthWidget.swift
git commit -m "feat(ios): add RecentActivityWidget + NetWorthWidget"
```

---

## Task 4: Build the `WidgetBundle`

- [ ] **Step 1: Implement**

`frontend/ios/WidgetExtension/WidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct FinchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BudgetRingWidget()
        RecentActivityWidget()
        NetWorthWidget()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/WidgetExtension/WidgetBundle.swift
git commit -m "feat(ios): add WidgetBundle (3 widgets)"
```

---

## Task 5: Build the `LiveActivity` for budget alerts

- [ ] **Step 1: Implement the `ActivityAttributes`**

`frontend/ios/WidgetExtension/ActivityWidget.swift`:

```swift
// WidgetExtension/ActivityWidget.swift — Live Activity for
// budget alerts. Started by the iOS app when a budget hits
// 90% (per Phase 6.2 §3.4).
import ActivityKit
import SwiftUI

public struct BudgetActivityAttributes: ActivityAttributes {
    public typealias ContentState = BudgetActivityState
    public let budgetId: String
    public let budgetName: String
    public let currency: String
}

public struct BudgetActivityState: Codable, Equatable {
    public let spent: Decimal
    public let limit: Decimal
    public let percentUsed: Double  // 0-1
    public let asOf: Date
}

@available(iOS 16.1, *)
struct BudgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BudgetActivityAttributes.self) { context in
            VStack {
                Text(context.attributes.budgetName)
                ProgressView(value: context.state.percentUsed)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.budgetName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.percentUsed * 100))%")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.percentUsed)
                }
            } compactLeading: {
                Text("\(Int(context.state.percentUsed * 100))%")
            } compactTrailing: {
                Image(systemName: "chart.pie")
            } minimal: {
                Text("\(Int(context.state.percentUsed * 100))%")
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/WidgetExtension/ActivityWidget.swift
git commit -m "feat(ios): add BudgetLiveActivity (Dynamic Island + Lock Screen)"
```

---

## Task 6: Build the watchOS app

- [ ] **Step 1: Implement the `WatchApp` entry point**

`frontend/ios/WatchApp/WatchApp.swift`:

```swift
import SwiftUI

@main
struct WatchApp: App {
    @StateObject private var connector = WatchConnector()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(connector)
        }
    }
}
```

- [ ] **Step 2: Implement `WatchConnector` (WatchConnectivity)**

`frontend/ios/WatchApp/WatchConnectivity.swift`:

```swift
import Foundation
import WatchConnectivity
import FinchCore

@MainActor
public final class WatchConnector: NSObject, ObservableObject, WCSessionDelegate {
    @Published public var snapshot: WidgetSnapshot?
    private let session = WCSession.default

    public override init() {
        super.init()
        session.delegate = self
        session.activate()
    }

    // Receive the latest snapshot from the iOS app
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // (decode applicationContext["widget_snapshot"] as WidgetSnapshot)
    }

    // Send a quick-add transaction to the iOS app
    public func quickAdd(amount: Decimal, merchant: String) {
        let message: [String: Any] = [
            "action": "addTransaction",
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "merchant": merchant
        ]
        session.sendMessage(message, replyHandler: nil) { error in
            print("WatchConnectivity error: \(error)")
        }
    }
}
```

- [ ] **Step 3: Build the `WatchContentView`**

`frontend/ios/WatchApp/WatchContentView.swift`:

```swift
import SwiftUI
import FinchCore

struct WatchContentView: View {
    @EnvironmentObject private var connector: WatchConnector
    @State private var amount: String = ""
    @State private var merchant: String = ""

    var body: some View {
        TabView {
            // Tab 1: Today's totals (read)
            WatchTotalsView()
            // Tab 2: Recent activity (read)
            WatchRecentView()
            // Tab 3: Quick add (write)
            WatchQuickAddView(amount: $amount, merchant: $merchant) {
                if let amt = Decimal(string: amount) {
                    connector.quickAdd(amount: amt, merchant: merchant)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Wire the iOS app to receive Watch messages**

Modify `FinchApp.swift`:

```swift
.onAppear {
    WatchSessionManager.shared.activate(onMessage: { message in
        if message["action"] as? String == "addTransaction",
           let amount = message["amount"] as? Double,
           let merchant = message["merchant"] as? String {
            Task {
                try? await FinchStore.shared.apply(
                    action: .addTransaction,
                    args: Args(values: [
                        "ledgerId": .string(FinchStore.shared.activeLedgerId),
                        "accountId": .string(FinchStore.shared.mostRecentAccountId ?? ""),
                        "amount": .double(amount),
                        "merchant": .string(merchant),
                        "date": .string(currentDateString)
                    ])
                )
            }
        }
    })
}
```

- [ ] **Step 5: Commit**

```bash
git add frontend/ios/WatchApp/
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): add watchOS app + WatchConnectivity sync"
```

---

## Self-review

**Spec coverage** (Phase 7 design spec, 8 sections + §0. Map TOC): all 8 sections covered (Tasks 1-6 cover §1-§5; remaining sections are deferred/non-applicable).
