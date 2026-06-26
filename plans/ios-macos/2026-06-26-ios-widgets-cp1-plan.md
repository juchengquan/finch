# Widgets CP1 (lock-screen / accessory families) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Offer finch's widget on the lock screen — add the three accessory families to the existing FinchOverview widget.

**Architecture:** `ios/FinchWidget/FinchWidget.swift` only. Add accessory families to `supportedFamilies` and branch `FinchWidgetView` on `@Environment(\.widgetFamily)`. Reuses the existing `WidgetSnapshot` + `AppGroup` reader. No engine/snapshot/App-Group change.

**Tech Stack:** SwiftUI + WidgetKit (iOS 17), XcodeGen.

## Global Constraints

- **No engine/snapshot/plumbing change.** Reuse `WidgetSnapshot` (`netWorth`/`currency`/`budgetUsedPct`/`weeklySpent`) + `AppGroup.readWidgetSnapshot()` + the existing `money(_:_:)` formatter.
- Keep `.systemSmall`/`.systemMedium` exactly as-is (the current layout becomes the `default` branch).
- Accessory families render on the lock screen (vibrant); use `.widgetAccentable()` on the key value and a `.clear` container background for accessory, opaque for system.
- **Must build iOS AND macOS (FinchMac).** The `FinchApp` build embeds + compiles `FinchWidget`. `xcodegen generate` first. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. No new unit tests (view-only); keep existing FinchCore/FinchApp tests green.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (widget):** `ios/FinchWidget/FinchWidget.swift`.

---

### Task 1: Accessory families on the FinchOverview widget

**Files:**
- Modify: `ios/FinchWidget/FinchWidget.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot` (`netWorth`/`currency`/`budgetUsedPct`/`weeklySpent`), `AppGroup.readWidgetSnapshot()`, the existing `money(_:_:)` helper.

- [ ] **Step 1: Add the accessory families to `supportedFamilies`**

In `FinchWidget.body`, change:
```swift
        .supportedFamilies([.systemSmall, .systemMedium])
```
to:
```swift
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
```

- [ ] **Step 2: Branch `FinchWidgetView` by widget family**

Replace the `FinchWidgetView` struct with a family-branched version (the current layout becomes `systemLayout`; the `money(_:_:)` helper is unchanged):

```swift
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
```
(Note: the system layout's `.padding()` stays inside `systemLayout`; `.containerBackground` is applied per-branch in `body`. The old single trailing `.containerBackground(.fill.tertiary, for: .widget)` on the body is removed — it's now per-branch.)

- [ ] **Step 3: Build iOS (compiles + embeds the widget)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Full FinchApp + FinchCore suites (regression)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"
```
Expected: `** TEST SUCCEEDED **`; FinchCore all pass.

- [ ] **Step 5: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification on the simulator**

Install the app (so the widget extension registers), then add the lock-screen widgets:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch   # launch once so the snapshot is written
```
Then in the simulator: **lock the device** (or Settings → Wallpaper / "Customize Lock Screen") → add widgets → finch shows **circular** (budget ring), **rectangular** (net worth + budget% · week), and **inline** (above the clock). Home-screen small/medium are unchanged. (Lock-screen widget editing in the sim is fiddly; the Home Screen "Add Widget" gallery also lists the families — the key check is that finch appears with all five sizes and renders without clipping.)

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchWidget/FinchWidget.swift
git commit -m "feat(ios): lock-screen widgets — accessoryCircular/Rectangular/Inline"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-widgets-cp1-design.md`):
- `supportedFamilies` + the 3 accessory families → Step 1. ✓
- Family-branched view (circular budget ring / rectangular net worth+budget%+week / inline net worth); system layout preserved as default → Step 2. ✓
- `.widgetAccentable` on the value + per-branch container background (clear for accessory, tertiary for system) → Step 2. ✓
- Nil-snapshot "—" via the existing `money(nil,…)` → Step 2 (helper unchanged). ✓
- No engine/snapshot change; build iOS+macOS; tests green → Steps 3-5. ✓

**Placeholder scan:** No TBD/TODO; full code; sim step concrete. ✓

**Type consistency:** `@Environment(\.widgetFamily)`; `WidgetSnapshot.netWorth/currency/budgetUsedPct/weeklySpent` consumed via `pct`/`nw`/`wk`; `money(_:_:)` unchanged; `Gauge`/`.accessoryCircular`/`.accessoryCircularCapacity` are WidgetKit/SwiftUI iOS-16+ APIs (target iOS 17). The widget still reads `AppGroup.readWidgetSnapshot()` unchanged. ✓

---

## Out of scope (later)

A dedicated Budget/account widget + configurable `AppIntentConfiguration` + richer per-account snapshot (CP2); interactive quick-add `Button(intent:)` (CP3); the Watch complication (separate sub-project).
