# Recurring-charge detector — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Detect repeating expense subscriptions and surface untracked ones on the Scheduled tab.

**Architecture:** Additive `Selectors.detectRecurring` + a `RecurringCharge` struct (FinchCore); a read-only "Detected · not scheduled" section in `ScheduledTab`. No change to existing selectors.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-26-recurring-detector-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. `detectRecurring` is additive (parity-safe). PR targets `feat/frontend`.

---

### Task 1: Engine — `RecurringCharge` + `detectRecurring`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift` (add the struct)
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (add the selector + helpers)
- Test: `ios/FinchCore/Tests/FinchCoreTests/DetectRecurringTests.swift` (create)

- [ ] **Step 1: Add the `RecurringCharge` struct**

In `Models.swift`, near the other selector result structs (e.g. after `MerchantStats`), add:

```swift
public struct RecurringCharge: Identifiable, Equatable, Sendable, Codable {
    public let id: String              // = merchantKey
    public let merchantName: String
    public let averageAmount: Double
    public let cadence: String         // weekly | biweekly | monthly | quarterly | yearly
    public let monthlyEstimate: Double
    public let occurrences: Int
    public let lastDate: String
    public let nextEstimatedDate: String
    public let isScheduled: Bool
    public init(id: String, merchantName: String, averageAmount: Double, cadence: String,
                monthlyEstimate: Double, occurrences: Int, lastDate: String,
                nextEstimatedDate: String, isScheduled: Bool) {
        self.id = id; self.merchantName = merchantName; self.averageAmount = averageAmount
        self.cadence = cadence; self.monthlyEstimate = monthlyEstimate; self.occurrences = occurrences
        self.lastDate = lastDate; self.nextEstimatedDate = nextEstimatedDate; self.isScheduled = isScheduled
    }
}
```

- [ ] **Step 2: Write the failing test**

Create `DetectRecurringTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class DetectRecurringTests: XCTestCase {
    private func exp(_ id: String, _ merchant: String, _ amount: Double, _ date: String, tmpl: String? = nil) -> Tx {
        Tx(id: id, merchant: merchant, amount: amount, account: "a1", date: date,
           pending: false, ledgerId: "l1", kind: "expense", sourceTemplateId: tmpl)
    }

    func test_detectsMonthlySubscription() {
        let txns = [
            exp("1", "Netflix", -15.99, "2026-03-03"),
            exp("2", "Netflix", -15.99, "2026-04-03"),
            exp("3", "Netflix", -15.99, "2026-05-03"),
            exp("4", "Netflix", -15.99, "2026-06-03"),
            // one-off noise — must NOT be detected
            exp("5", "Random Shop", -42.10, "2026-05-10"),
        ]
        let out = Selectors.detectRecurring(txns, "l1", "2026-06-20")
        XCTAssertEqual(out.count, 1)
        let r = out[0]
        XCTAssertEqual(r.merchantName, "Netflix")
        XCTAssertEqual(r.cadence, "monthly")
        XCTAssertEqual(r.occurrences, 4)
        XCTAssertEqual(r.averageAmount, 15.99, accuracy: 0.01)
        XCTAssertEqual(r.monthlyEstimate, 15.99, accuracy: 0.01)
        XCTAssertFalse(r.isScheduled)
    }

    func test_irregularGaps_notDetected() {
        let txns = [
            exp("1", "Cafe", -5, "2026-06-01"),
            exp("2", "Cafe", -5, "2026-06-02"),
            exp("3", "Cafe", -5, "2026-06-19"),
        ]
        XCTAssertTrue(Selectors.detectRecurring(txns, "l1", "2026-06-20").isEmpty)
    }

    func test_stale_droppedByActiveFilter() {
        let txns = [
            exp("1", "OldGym", -20, "2025-01-05"),
            exp("2", "OldGym", -20, "2025-02-05"),
            exp("3", "OldGym", -20, "2025-03-05"),
        ]
        XCTAssertTrue(Selectors.detectRecurring(txns, "l1", "2026-06-20").isEmpty)
    }

    func test_isScheduled_whenSourcedFromTemplate() {
        let txns = [
            exp("1", "Rent", -1000, "2026-04-01", tmpl: "tmpl-rent"),
            exp("2", "Rent", -1000, "2026-05-01", tmpl: "tmpl-rent"),
            exp("3", "Rent", -1000, "2026-06-01", tmpl: "tmpl-rent"),
        ]
        let out = Selectors.detectRecurring(txns, "l1", "2026-06-20")
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].isScheduled)
    }
}
```

- [ ] **Step 3: Run — expect FAIL** (`cd ios/FinchCore && swift test --filter DetectRecurringTests 2>&1 | tail -15`) — no such function.

- [ ] **Step 4: Add the selector + helpers**

In `Selectors.swift` (in the `Selectors` enum, near `merchantStats`), add:

```swift
    /// Detect repeating expense charges (subscriptions). Groups expenses by merchant,
    /// keeps those with a consistent cadence + stable amount that are still active.
    public static func detectRecurring(_ txns: [Tx], _ ledgerId: String, _ today: String,
                                       minOccurrences: Int = 3) -> [RecurringCharge] {
        var groups: [String: [Tx]] = [:]
        var names: [String: String] = [:]
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            if kindOf(t) != "expense" { continue }
            guard let key = merchantKey(t) else { continue }
            groups[key, default: []].append(t)
            names[key] = t.merchant
        }
        let todayDate = date(today)
        var out: [RecurringCharge] = []
        for (key, raw) in groups {
            let items = raw.sorted { ($0.date, $0.time ?? "") < ($1.date, $1.time ?? "") }
            guard items.count >= minOccurrences else { continue }

            let mags = items.map { abs($0.nativeAmount ?? $0.amount) }
            let mean = mags.reduce(0, +) / Double(mags.count)
            guard mean > 0 else { continue }
            let variance = mags.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(mags.count)
            guard variance.squareRoot() / mean < 0.35 else { continue }   // amounts roughly equal

            var gaps: [Int] = []
            for i in 1..<items.count {
                let g = cal.dateComponents([.day], from: date(items[i-1].date), to: date(items[i].date)).day ?? 0
                if g > 0 { gaps.append(g) }
            }
            guard !gaps.isEmpty else { continue }
            let med = medianInt(gaps)
            guard let cadence = cadenceForGap(med) else { continue }
            guard gaps.allSatisfy({ abs(Double($0) - Double(med)) <= 0.4 * Double(med) }) else { continue }

            let lastDate = items.last!.date
            let sinceLast = cal.dateComponents([.day], from: date(lastDate), to: todayDate).day ?? 0
            guard sinceLast <= Int(1.6 * Double(med)) else { continue }    // still active

            let isScheduled = items.contains { ($0.sourceTemplateId?.isEmpty == false) }
            out.append(RecurringCharge(
                id: key, merchantName: names[key] ?? key, averageAmount: r2(mean), cadence: cadence,
                monthlyEstimate: r2(monthlyFor(mean, cadence)), occurrences: items.count,
                lastDate: lastDate, nextEstimatedDate: ymd(addDays(date(lastDate), med)), isScheduled: isScheduled))
        }
        return out.sorted { $0.monthlyEstimate > $1.monthlyEstimate }
    }

    private static func medianInt(_ xs: [Int]) -> Int {
        let s = xs.sorted(); let n = s.count
        return n % 2 == 1 ? s[n/2] : (s[n/2 - 1] + s[n/2]) / 2
    }
    private static func cadenceForGap(_ g: Int) -> String? {
        switch g {
        case 6...8: return "weekly"
        case 12...16: return "biweekly"
        case 26...35: return "monthly"
        case 80...100: return "quarterly"
        case 350...380: return "yearly"
        default: return nil
        }
    }
    private static func monthlyFor(_ amount: Double, _ cadence: String) -> Double {
        switch cadence {
        case "weekly": return amount * 30.0 / 7.0
        case "biweekly": return amount * 30.0 / 14.0
        case "quarterly": return amount / 3.0
        case "yearly": return amount / 12.0
        default: return amount   // monthly
        }
    }
```
(`ledgerOf`, `kindOf`, `merchantKey`, `r2`, `cal`, `date`, `ymd`, `addDays` already exist in this file.)

- [ ] **Step 5: Run filtered + full suite**

```bash
cd ios/FinchCore && swift test --filter DetectRecurringTests 2>&1 | tail -12
swift test 2>&1 | tail -8
```
Expected: 4/4 filtered pass; full suite + ParityTests green.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Project/Models.swift \
        ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/DetectRecurringTests.swift
git commit -m "feat(ios): Selectors.detectRecurring (subscription detector)"
```

---

### Task 2: Scheduled-tab "Detected · not scheduled" section

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift`

- [ ] **Step 1: Add the `detected` computed**

In `struct ScheduledTab`, add (near the other computed/state):

```swift
    private var detected: [RecurringCharge] {
        Selectors.detectRecurring(store.txns, store.activeLedgerId, store.today).filter { !$0.isScheduled }
    }
    private var detectedMonthly: Double { detected.reduce(0) { $0 + $1.monthlyEstimate } }
```

- [ ] **Step 2: Update the empty-state gate**

Change:

```swift
                if store.scheduled.isEmpty {
                    ContentUnavailableView {
```
to:

```swift
                if store.scheduled.isEmpty && detected.isEmpty {
                    ContentUnavailableView {
```

- [ ] **Step 3: Add the detected section in list mode**

In the list-mode `List { ForEach(store.scheduled, id: \.id) { … } }`, **after** that
`ForEach`'s closing brace (still inside the `List`), add:

```swift
                                if !detected.isEmpty {
                                    Section {
                                        ForEach(detected) { r in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(r.merchantName)
                                                    Text("\(r.cadence.capitalized) · next ~\(r.nextEstimatedDate)")
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text(store.displayMoneyBase(r.averageAmount)).fontWeight(.medium)
                                            }
                                        }
                                    } header: {
                                        HStack {
                                            Text("Detected · not scheduled")
                                            Spacer()
                                            Text("~\(store.displayMoneyBase(detectedMonthly))/mo · \(detected.count)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
```

- [ ] **Step 4: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift
git commit -m "feat(ios): Scheduled tab — detected recurring (not scheduled) section"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + seed ~4 monthly equal expenses for one merchant**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install "$SIM" "$APP"; xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
# Seed via the app's Add flow OR insert 4 monthly "Netflix" expense entries in the live DB
# (find the live finch.sqlite3 with entries; dates ~monthly ending within the last cadence).
xcrun simctl launch "$SIM" com.juchengquan.finch
```
(If seeding via DB is impractical, add 4 monthly "Netflix" expenses through the app, dated ~the 3rd of the last 4 months.)

- [ ] **Step 2: Verify**
  - Scheduled tab → a **"Detected · not scheduled"** section lists Netflix (Monthly · ~amount) with a `~$X/mo · N` header total. A one-off merchant does not appear.
  - Screenshot evidence to `/tmp/recurring.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: struct (T1 S1) + test (T1 S2/S5) + selector & helpers (T1 S4), Scheduled section + empty-state fix (T2), build (T2 S4), manual (T3). ✓
- Type consistency: `detectRecurring(_:_:_:minOccurrences:)`, `RecurringCharge`, `store.displayMoneyBase`, `store.today` consistent. ✓
- Additive selector → ParityTests unaffected. ✓
