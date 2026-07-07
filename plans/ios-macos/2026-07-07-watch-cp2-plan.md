# Watch CP2 — watch-face complication — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a WidgetKit accessory complication (circular · corner · inline · rectangular) for the Apple Watch that renders the CP1 snapshot from the watch's App Group and refreshes when the phone pushes a new one.

**Architecture:** A new watchOS widget-extension target (`FinchWatchComplication`, embedded in `FinchWatch`) reads the snapshot `WatchSnapshotStore` already persists. Shared constants (`WatchStore.suite`/`key`) + display helpers (`shortMoney`, `isStale`) move into `ios/Shared/` so app, watch, and extension agree. The store calls `WidgetCenter.shared.reloadAllTimelines()` after each received context.

**Tech Stack:** Swift / SwiftUI / WidgetKit / WatchConnectivity; XcodeGen (`ios/project.yml`); XCTest (`FinchAppTests`). Spec: `plans/ios-macos/2026-07-07-watch-cp2-spec.md`.

## Global Constraints

- The watch stack stays **FinchCore-free**. The extension's only shared code is `ios/Shared/*` — Foundation-only (display helpers must not import SwiftUI/WidgetKit; formatting returns `String`s, staleness returns `Bool`; the views apply styling).
- App Group `group.com.juchengquan.finch`, key `watchSnapshot` — after this PR referenced ONLY via the new `WatchStore` constants (no string literals left in `WatchSnapshotStore` or the extension).
- Bundle id `com.juchengquan.finch.watch.complication` (watch-app-prefixed). `CODE_SIGNING_ALLOWED: NO` everywhere, same as existing targets.
- `WidgetCenter` import in `FinchWatchApp.swift` is watchOS-only code — no `#if` needed there (the file is only in the watch target), but Shared files compile into FinchApp AND FinchMac too, so they get no new imports at all.
- Run from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` after touching `project.yml` or adding files. Builds: FinchApp (iOS sim), FinchMac (`-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`), FinchWatch (`-destination 'generic/platform=watchOS Simulator'`).
- No new dependencies. No changes to `WidgetSnapshot`, the iOS widget, or FinchCore.

---

### Task 1: Shared constants + display helpers

**Files:**
- Create: `ios/Shared/WatchSnapshotPayload+Display.swift`
- Modify: `ios/FinchWatch/FinchWatchApp.swift` (switch `WatchSnapshotStore` to `WatchStore.suite`/`.key`)
- Test: `ios/FinchApp/Tests/FinchAppTests/WatchSnapshotDisplayTests.swift`

**Interfaces:**
- Produces: `enum WatchStore { static let suite: String; static let key: String }`; `extension WatchSnapshotPayload { func shortMoney(_ amount: Double) -> String; var isStale: Bool }`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchApp/Tests/FinchAppTests/WatchSnapshotDisplayTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class WatchSnapshotDisplayTests: XCTestCase {
    private func payload(generatedAt: Date = .now) -> WatchSnapshotPayload {
        WatchSnapshotPayload(netWorth: 0, currency: "USD", budgetUsedPct: 0,
                             weeklySpent: 0, generatedAt: generatedAt)
    }

    func test_shortMoney_belowThousand_noDecimals() {
        XCTAssertEqual(payload().shortMoney(842.4), "$842")
    }

    func test_shortMoney_thousands_oneDecimal() {
        XCTAssertEqual(payload().shortMoney(12_340), "$12.3K")
    }

    func test_shortMoney_respectsCurrency() {
        var p = payload(); p.currency = "JPY"
        XCTAssertEqual(p.shortMoney(1_200_000), "¥1.2M")
    }

    func test_isStale_boundary24h() {
        XCTAssertFalse(payload(generatedAt: Date(timeIntervalSinceNow: -23 * 3600)).isStale)
        XCTAssertTrue(payload(generatedAt: Date(timeIntervalSinceNow: -25 * 3600)).isStale)
    }

    func test_storeConstants() {
        XCTAssertEqual(WatchStore.suite, "group.com.juchengquan.finch")
        XCTAssertEqual(WatchStore.key, "watchSnapshot")
    }
}
```

- [ ] **Step 2: Run to confirm compile failure** (`cannot find 'WatchStore' in scope`):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/WatchSnapshotDisplayTests 2>&1 | grep -iE "cannot find|error:|TEST SUCCEEDED|TEST FAILED"
```

- [ ] **Step 3: Create `ios/Shared/WatchSnapshotPayload+Display.swift`**

```swift
import Foundation

/// Watch sub-project CP2 — shared App-Group constants + display helpers.
/// Foundation-only; compiled into FinchApp, FinchWatch, and the complication
/// extension so all three agree without a FinchCore dependency.
enum WatchStore {
    static let suite = "group.com.juchengquan.finch"
    static let key = "watchSnapshot"
}

extension WatchSnapshotPayload {
    /// Compact currency for tiny watch faces: "$842", "$12.3K", "¥1.2M".
    func shortMoney(_ amount: Double) -> String {
        let sym = symbol(for: currency)
        let mag = abs(amount)
        let sign = amount < 0 ? "-" : ""
        func trim(_ v: Double) -> String {
            let s = String(format: "%.1f", v)
            return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        if mag >= 1_000_000 { return "\(sign)\(sym)\(trim(mag / 1_000_000))M" }
        if mag >= 1_000 { return "\(sign)\(sym)\(trim(mag / 1_000))K" }
        return "\(sign)\(sym)\(Int(mag.rounded()))"
    }

    /// Older than 24h — complications dim rather than hide stale data.
    var isStale: Bool { Date().timeIntervalSince(generatedAt) > 24 * 3600 }

    private func symbol(for code: String) -> String {
        let locale = Locale.availableIdentifiers.lazy
            .map { Locale(identifier: $0) }
            .first { $0.currency?.identifier == code }
        return locale?.currencySymbol ?? code
    }
}
```

> ⚠️ The `symbol(for:)` scan above is O(locales) — if it measurably slows the
> test run, replace with a small static map for the currencies the app ships
> ("USD $", "SGD S$", "CNY ¥", "JPY ¥", "EUR €", "GBP £", fallback = code).
> Check what `12.3K` vs `12.3k` renders like against `FinchWidget`'s existing
> compact strings and match case with whatever the tests pin.

- [ ] **Step 4: Switch `WatchSnapshotStore` to the constants** — in `ios/FinchWatch/FinchWatchApp.swift` replace the two literals:

```swift
private let suite = UserDefaults(suiteName: WatchStore.suite)
private let key = WatchStore.key
```

- [ ] **Step 5: Re-run Step 2's command — TEST SUCCEEDED. Also build FinchWatch + FinchMac** (Shared compiles on all three platforms):

```bash
xcodebuild build -project FinchApp.xcodeproj -scheme FinchWatch \
  -destination 'generic/platform=watchOS Simulator' 2>&1 | grep -E "error:|BUILD"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6: Commit** — `feat(ios): watch CP2 task 1 — shared WatchStore constants + display helpers`

---

### Task 2: The complication extension target

**Files:**
- Create: `ios/FinchWatchComplication/FinchWatchComplication.swift`
- Create: `ios/FinchWatchComplication/Info.plist` (copy `ios/FinchWidget/Info.plist`, same `com.apple.widgetkit-extension` point)
- Create: `ios/FinchWatchComplication/FinchWatchComplication.entitlements` (copy `ios/FinchWatch/FinchWatch.entitlements` — the App Group)
- Modify: `ios/project.yml`

- [ ] **Step 1: Add the target to `project.yml`** — after the `FinchWatch` target block:

```yaml
  # Watch CP2 — the watch-face complication (WidgetKit accessory families).
  # Reads the snapshot WatchSnapshotStore persists to the watch App Group;
  # FinchCore-free like the rest of the watch stack.
  FinchWatchComplication:
    type: app-extension
    platform: watchOS
    sources:
      - path: FinchWatchComplication
      - path: Shared
    settings:
      base:
        INFOPLIST_FILE: FinchWatchComplication/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.juchengquan.finch.watch.complication
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_ENTITLEMENTS: FinchWatchComplication/FinchWatchComplication.entitlements
        CODE_SIGNING_ALLOWED: "NO"
        SKIP_INSTALL: "NO"
```

and embed it — in the `FinchWatch` target add:

```yaml
    dependencies:
      - target: FinchWatchComplication
```

- [ ] **Step 2: Create the widget** — `ios/FinchWatchComplication/FinchWatchComplication.swift`, mirroring `FinchWidgetView`'s accessory cases (see spec §4 for the family table):

```swift
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
```

- [ ] **Step 3: `xcodegen generate` + build FinchWatch** (now embeds the extension):

```bash
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchWatch \
  -destination 'generic/platform=watchOS Simulator' 2>&1 | grep -E "error:|BUILD"
```

Expected: BUILD SUCCEEDED, `FinchWatchComplication.appex` embedded (check the build log or `PlugIns/` in the product).

- [ ] **Step 4: Build FinchApp + FinchMac** — prove the new target/Shared file changed nothing cross-platform.

- [ ] **Step 5: Commit** — `feat(ios): watch CP2 task 2 — FinchWatchComplication widget extension (4 accessory families)`

---

### Task 3: Reload-on-push + hand verification

**Files:**
- Modify: `ios/FinchWatch/FinchWatchApp.swift`

- [ ] **Step 1: Reload complications when a context arrives** — in `WatchSnapshotStore.session(_:didReceiveApplicationContext:)`, after `self.snapshot = incoming`:

```swift
import WidgetKit   // top of file

WidgetCenter.shared.reloadAllTimelines()
```

- [ ] **Step 2: Rebuild FinchWatch** — green.

- [ ] **Step 3: Hand-verify in the simulator** (watch faces aren't reachable via AX automation — do this manually, screenshot for the PR):

1. Run FinchWatch in a paired watchOS simulator (`xcrun simctl list | grep -i watch` for the pair).
2. Long-press the face → Edit → add the finch complication in circular, corner, inline, rectangular slots → placeholder shows `—` / empty gauge.
3. Run FinchApp on the paired iPhone sim, import/mutate demo data → the phone pushes a context (CP1) → wake the watch face → complication shows live figures.
4. Note in the PR: `isPaired`/`isWatchAppInstalled` behave loosely on simulators — if the context doesn't arrive, foreground the watch app once (delivery on next wake is expected WCSession behaviour, not a bug).

- [ ] **Step 4: Update docs** — `plans/ios-macos/2026-06-25-ios-handoff.md`: Watch row → "🟡 CP1+CP2 done (#412, #this) — on-wrist quick-add (CP3) remains"; add the PR to the session log. `IOS_MACOS_ROADMAP.md` Phase 7 note if it names the complication as open.

- [ ] **Step 5: Commit** — `feat(ios): watch CP2 task 3 — reload complications on snapshot push + docs`

---

## Acceptance criteria

- FinchWatch build embeds `FinchWatchComplication.appex`; FinchApp / FinchMac / FinchCore `swift test` / ParityTests all stay green.
- `FinchAppTests/WatchSnapshotDisplayTests` green (shortMoney thresholds, isStale boundary, WatchStore constants).
- No `group.com.juchengquan.finch` / `watchSnapshot` string literals outside `WatchStore`.
- Hand-verified: all four families render on a simulator watch face; a phone-side data change propagates to the complication.
- The watch stack still has zero FinchCore imports.
