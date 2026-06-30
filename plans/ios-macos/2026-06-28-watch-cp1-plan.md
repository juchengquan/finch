# Watch CP1 — WCSession transport + working glance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Apple Watch glance show real, current data by pushing the phone's snapshot to the watch over `WCSession` (App Groups don't span devices).

**Architecture:** A shared Foundation-only `WatchSnapshotPayload` (compiled into both `FinchApp` and `FinchWatch`) is the wire format. The phone (`PhoneWatchLink`, iOS-only) builds it at the existing snapshot-write site and sends it via `WCSession.updateApplicationContext`. The watch (`WatchSnapshotStore`) receives it, persists to its own App Group, and the glance renders it.

**Tech Stack:** Swift / SwiftUI / WatchConnectivity; XcodeGen (`ios/project.yml`); XCTest (`FinchAppTests`). Spec: `plans/ios-macos/2026-06-28-watch-cp1-spec.md`.

## Global Constraints

- **`WatchConnectivity` is unavailable on macOS**, and `FinchMac` compiles `FinchApp/Sources/FinchApp` — so all phone-side WCSession code (`PhoneWatchLink`, the `WatchSnapshotPayload(widget:)` mapping, the push call, the activate call) MUST be wrapped in `#if os(iOS)`. Build `FinchMac` to prove it.
- The watch stays **FinchCore-free**. The only shared code is `ios/Shared/WatchSnapshotPayload.swift` — Foundation only, no FinchCore/SwiftUI/WatchConnectivity imports.
- App Group id is `group.com.juchengquan.finch` (already in the watch entitlements).
- Transport is `WCSession.updateApplicationContext(["snapshot": data])` where `data` is the JSON-encoded payload. All phone pushes guard `WCSession.isSupported()`, `activationState == .activated`, `isPaired`, `isWatchAppInstalled` — inert for phone-only users.
- Payload fields = the four the glance already shows + a timestamp: `netWorth: Double`, `currency: String`, `budgetUsedPct: Int`, `weeklySpent: Double`, `generatedAt: Date`.
- Run from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` after touching `project.yml` or adding files. Builds: FinchApp (iOS sim), FinchMac (`-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`), FinchWatch (`-destination 'generic/platform=watchOS Simulator'`).
- No new dependencies. No changes to `WidgetSnapshot`/widgets/FinchCore.

---

### Task 1: Shared `WatchSnapshotPayload` wire format

**Files:**
- Create: `ios/Shared/WatchSnapshotPayload.swift`
- Modify: `ios/project.yml` (add `Shared` to `FinchApp` and `FinchWatch` sources)
- Test: `ios/FinchApp/Tests/FinchAppTests/WatchSnapshotPayloadTests.swift`

**Interfaces:**
- Produces: `struct WatchSnapshotPayload: Codable, Equatable { var netWorth: Double; var currency: String; var budgetUsedPct: Int; var weeklySpent: Double; var generatedAt: Date }`, `func encoded() -> Data?`, `static func decode(_ data: Data) -> WatchSnapshotPayload?`.

- [ ] **Step 1: Write the failing round-trip test**

Create `ios/FinchApp/Tests/FinchAppTests/WatchSnapshotPayloadTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class WatchSnapshotPayloadTests: XCTestCase {
    func test_encodeDecodeRoundTrip() throws {
        let p = WatchSnapshotPayload(netWorth: 1234.5, currency: "USD",
                                     budgetUsedPct: 42, weeklySpent: 78.9,
                                     generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try XCTUnwrap(p.encoded())
        let back = try XCTUnwrap(WatchSnapshotPayload.decode(data))
        XCTAssertEqual(p, back)
    }

    func test_decodeGarbageReturnsNil() {
        XCTAssertNil(WatchSnapshotPayload.decode(Data([0x00, 0x01, 0x02])))
    }
}
```

- [ ] **Step 2: Run it to confirm it fails (type doesn't exist yet)**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/WatchSnapshotPayloadTests 2>&1 | grep -iE "cannot find|error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL to compile — `cannot find 'WatchSnapshotPayload' in scope`.

- [ ] **Step 3: Create the shared payload file**

Create `ios/Shared/WatchSnapshotPayload.swift`:

```swift
import Foundation

/// Watch sub-project CP1 — the phone→watch wire format. Foundation-only and
/// compiled into BOTH FinchApp and FinchWatch so the two sides agree on the shape
/// without the watch depending on FinchCore. Sent via
/// `WCSession.updateApplicationContext(["snapshot": data])`.
struct WatchSnapshotPayload: Codable, Equatable {
    var netWorth: Double
    var currency: String
    var budgetUsedPct: Int
    var weeklySpent: Double
    var generatedAt: Date

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> WatchSnapshotPayload? {
        try? JSONDecoder().decode(WatchSnapshotPayload.self, from: data)
    }
}
```

- [ ] **Step 4: Wire the file into both targets in `project.yml`**

In `ios/project.yml`, add `Shared` to the `sources` of `FinchApp` and `FinchWatch` (leave `FinchMac` as-is — the type is only referenced from `#if os(iOS)` code, so macOS never needs it).

`FinchApp`:
```yaml
    sources:
      - path: FinchApp/Sources/FinchApp
      - path: Shared
```
`FinchWatch`:
```yaml
    sources:
      - path: FinchWatch
      - path: Shared
```

- [ ] **Step 5: Run the test (now passes) + confirm FinchWatch compiles with the shared file**

```bash
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/WatchSnapshotPayloadTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchWatch \
  -destination 'generic/platform=watchOS Simulator' 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **` (FinchWatch). If the watchOS build can't run in this environment, note it and rely on the iOS compile of the shared file.

- [ ] **Step 6: Commit**

```bash
git add ios/Shared/WatchSnapshotPayload.swift ios/project.yml \
        ios/FinchApp/Tests/FinchAppTests/WatchSnapshotPayloadTests.swift
git commit -m "feat(ios): shared WatchSnapshotPayload wire format (Watch CP1)"
```

---

### Task 2: Phone `PhoneWatchLink` + push hook

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Watch/PhoneWatchLink.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Widgets/WidgetSnapshot.swift` (push after the existing write)
- Modify: `ios/FinchApp/Sources/FinchApp/FinchApp.swift` (activate at launch)
- Test: `ios/FinchApp/Tests/FinchAppTests/WatchSnapshotPayloadTests.swift` (add a mapping test)

**Interfaces:**
- Consumes: `WatchSnapshotPayload` (Task 1); `FinchCore.WidgetSnapshot` (fields `netWorth`, `currency`, `budgetUsedPct`, `weeklySpent`); `WidgetSnapshotWriter.build/write(from:)`.
- Produces (iOS-only): `PhoneWatchLink.shared`, `PhoneWatchLink.activate()`, `PhoneWatchLink.push(_:)`, and `WatchSnapshotPayload.init(widget: WidgetSnapshot)`.

- [ ] **Step 1: Write the failing mapping test**

Append to `ios/FinchApp/Tests/FinchAppTests/WatchSnapshotPayloadTests.swift` (inside the class):

```swift
    func test_initFromWidgetSnapshot_copiesGlanceFields() {
        let snap = WidgetSnapshot(netWorth: 100, currency: "EUR", budgetUsedPct: 33,
                                  weeklySpent: 12, generatedAt: "x", accounts: nil, budgets: nil)
        let p = WatchSnapshotPayload(widget: snap)
        XCTAssertEqual(p.netWorth, 100)
        XCTAssertEqual(p.currency, "EUR")
        XCTAssertEqual(p.budgetUsedPct, 33)
        XCTAssertEqual(p.weeklySpent, 12)
    }
```
Add `import FinchCore` at the top of the test file (for `WidgetSnapshot`).

- [ ] **Step 2: Run it to confirm it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/WatchSnapshotPayloadTests 2>&1 | grep -iE "cannot find|error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL — `extra argument 'widget'` / `cannot find` (the init doesn't exist).

- [ ] **Step 3: Create `PhoneWatchLink.swift` (iOS-only) with the mapping**

Create `ios/FinchApp/Sources/FinchApp/Watch/PhoneWatchLink.swift`:

```swift
#if os(iOS)
import Foundation
import WatchConnectivity
import FinchCore

/// Watch sub-project CP1 — pushes the latest snapshot to the paired Apple Watch
/// via `WCSession.updateApplicationContext` (latest-state, coalescing; App Groups
/// don't span devices). iOS-only: WatchConnectivity is unavailable on macOS, and
/// FinchMac shares these sources.
final class PhoneWatchLink: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchLink()

    /// Activate once at launch (no-op if the device has no WCSession support).
    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Send the latest payload to the watch. Inert unless a watch app is installed.
    func push(_ payload: WatchSnapshotPayload) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled,
              let data = payload.encoded() else { return }
        try? s.updateApplicationContext(["snapshot": data])
    }

    // MARK: WCSessionDelegate (iOS-required stubs)
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }  // re-activate for watch switching
}

extension WatchSnapshotPayload {
    /// Map the phone's WidgetSnapshot to the watch wire format (the four glance
    /// fields + a fresh timestamp).
    init(widget snap: WidgetSnapshot) {
        self.init(netWorth: snap.netWorth, currency: snap.currency,
                  budgetUsedPct: snap.budgetUsedPct, weeklySpent: snap.weeklySpent,
                  generatedAt: Date())
    }
}
#endif
```

- [ ] **Step 4: Run the mapping test (now passes)**

```bash
cd ios && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/WatchSnapshotPayloadTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Hook the push into the existing snapshot-write site**

In `ios/FinchApp/Sources/FinchApp/Widgets/WidgetSnapshot.swift`, change `write(from:)` from:
```swift
    public static func write(from store: FinchStore) {
        let snap = build(from: store)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: AppGroup.widgetSnapshotURL) }
    }
```
to:
```swift
    public static func write(from store: FinchStore) {
        let snap = build(from: store)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: AppGroup.widgetSnapshotURL) }
        #if os(iOS)
        PhoneWatchLink.shared.push(WatchSnapshotPayload(widget: snap))
        #endif
    }
```
(This single site is already called from both `FinchStore` and `FinchStore+ImportExport`, so both write paths now push to the watch — DRY.)

- [ ] **Step 6: Activate the link at launch**

In `ios/FinchApp/Sources/FinchApp/FinchApp.swift`, inside the existing `.task { … }` block (e.g. right after `store.bootstrap()`), add:
```swift
                #if os(iOS)
                PhoneWatchLink.shared.activate()
                #endif
```

- [ ] **Step 7: Build iOS + macOS (proves the `#if os(iOS)` guards keep FinchMac green)**

```bash
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Watch/PhoneWatchLink.swift \
        ios/FinchApp/Sources/FinchApp/Widgets/WidgetSnapshot.swift \
        ios/FinchApp/Sources/FinchApp/FinchApp.swift \
        ios/FinchApp/Tests/FinchAppTests/WatchSnapshotPayloadTests.swift
git commit -m "feat(ios): PhoneWatchLink — push snapshot to the watch via WCSession (Watch CP1)"
```

---

### Task 3: Watch receiver + working glance

**Files:**
- Modify (rewrite): `ios/FinchWatch/FinchWatchApp.swift`

**Interfaces:**
- Consumes: `WatchSnapshotPayload` (Task 1, compiled into FinchWatch); `WCSession` application-context delivery from `PhoneWatchLink` (Task 2).

- [ ] **Step 1: Rewrite `FinchWatchApp.swift` — receiver + persistence + glance**

Replace the entire contents of `ios/FinchWatch/FinchWatchApp.swift` with:

```swift
import SwiftUI
import WatchConnectivity

/// Watch sub-project CP1 — the standalone watchOS glance. App Groups don't span
/// devices, so the watch can't read the phone's container; instead it receives the
/// phone's snapshot over WCSession (see PhoneWatchLink), persists it to its OWN App
/// Group, and renders it. Uses the shared `WatchSnapshotPayload` wire format.
final class WatchSnapshotStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: WatchSnapshotPayload?
    private let suite = UserDefaults(suiteName: "group.com.juchengquan.finch")
    private let key = "watchSnapshot"

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
```

- [ ] **Step 2: Build FinchWatch (watchOS) + iOS regression**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchWatch \
  -destination 'generic/platform=watchOS Simulator' 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: both `** BUILD SUCCEEDED **`. (If the watchOS simulator build can't run in this environment, report that limitation explicitly; the code is otherwise self-contained.)

- [ ] **Step 3: Live round-trip (best-effort) + report**

If a paired iPhone+Watch simulator is available: install both, mutate data on the phone, confirm the watch glance updates (or shows "No data yet" then populates). If not feasible, state in the report that the live path was verified by code inspection only (the delegate wiring is symmetric: phone `updateApplicationContext(["snapshot": data])` ↔ watch `didReceiveApplicationContext`, both using `WatchSnapshotPayload`).

- [ ] **Step 4: Commit**

```bash
git add ios/FinchWatch/FinchWatchApp.swift
git commit -m "feat(ios): watch receives snapshot over WCSession + working glance (Watch CP1)"
```

---

## Self-Review

**1. Spec coverage:**
- WCSession transport via `updateApplicationContext` → Task 2 (push) + Task 3 (receive). ✅
- Shared Foundation-only `WatchSnapshotPayload` in both targets → Task 1. ✅
- Phone hook at the existing snapshot-write site, factored (DRY) → Task 2 Step 5 (`WidgetSnapshotWriter.write`). ✅
- Phone activates at launch + inertness guards → Task 2 Steps 3, 6. ✅
- Watch persists to its own App Group + loads last-known on launch + ignores stale → Task 3 Step 1. ✅
- Glance observes the store + empty state → Task 3 Step 1. ✅
- `#if os(iOS)` so FinchMac stays green → Global Constraints + Task 2 (file, hook, activate) + Task 2 Step 7 build. ✅
- Unit tests (round-trip + mapping) → Task 1 Step 1, Task 2 Step 1. ✅
- Builds FinchApp + FinchMac + FinchWatch → Task 1 Step 5, Task 2 Step 7, Task 3 Step 2. ✅
- Live round-trip best-effort/by-inspection → Task 3 Step 3. ✅

**2. Placeholder scan:** none — every code step has complete code; commands have expected output.

**3. Type consistency:** `WatchSnapshotPayload` fields/`encoded()`/`decode(_:)` (Task 1) are used identically by `PhoneWatchLink`/`init(widget:)` (Task 2) and `WatchSnapshotStore` (Task 3). The `["snapshot": data]` application-context key matches on both sides. `WidgetSnapshot(netWorth:currency:budgetUsedPct:weeklySpent:generatedAt:accounts:budgets:)` matches the real initializer used by `WidgetSnapshotWriter.build`.
