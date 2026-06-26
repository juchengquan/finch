# Add to Scheduled — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Checkbox steps.

**Goal:** Tap a detected recurring charge → pre-filled `ScheduledSheet` → create a template; the row clears once added.

**Architecture:** `RecurringCharge` gains modal `accountId`/`categoryId`; `detectRecurring` gains a `scheduled` param (name-match `isScheduled`); `ScheduledSheet` gets a prefill init; the Scheduled-tab detected rows become tappable.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-26-add-to-scheduled-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. Additive selector change (parity-safe). PR targets `feat/frontend`.

---

### Task 1: Engine — modal account/category + name-match `isScheduled`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift` (`RecurringCharge`)
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (`detectRecurring` + `mode`)
- Modify: `ios/FinchCore/Tests/FinchCoreTests/DetectRecurringTests.swift`

- [ ] **Step 1: Add fields to `RecurringCharge`**

In `Models.swift`, in `struct RecurringCharge`, add the two properties after `isScheduled`:

```swift
    public let accountId: String?
    public let categoryId: String?
```
And extend the `init` — add the two params (at the end) + assignments:

```swift
                nextEstimatedDate: String, isScheduled: Bool,
                accountId: String?, categoryId: String?) {
```
```swift
        self.lastDate = lastDate; self.nextEstimatedDate = nextEstimatedDate; self.isScheduled = isScheduled
        self.accountId = accountId; self.categoryId = categoryId
```

- [ ] **Step 2: Extend the tests (expect FAIL — new init args / param)**

In `DetectRecurringTests.swift`, update the existing `exp` helper to allow account/category and add two tests:

```swift
    private func exp(_ id: String, _ merchant: String, _ amount: Double, _ date: String,
                    tmpl: String? = nil, acct: String = "a1", cat: String? = "food") -> Tx {
        Tx(id: id, merchant: merchant, category: cat, amount: amount, account: acct, date: date,
           pending: false, ledgerId: "l1", kind: "expense", sourceTemplateId: tmpl)
    }

    func test_carriesModalAccountAndCategory() {
        let txns = [
            exp("1", "Netflix", -15.99, "2026-03-03", acct: "a1", cat: "ent"),
            exp("2", "Netflix", -15.99, "2026-04-03", acct: "a1", cat: "ent"),
            exp("3", "Netflix", -15.99, "2026-05-03", acct: "a2", cat: "ent"),
            exp("4", "Netflix", -15.99, "2026-06-03", acct: "a1", cat: "ent"),
        ]
        let r = Selectors.detectRecurring(txns, "l1", "2026-06-20")[0]
        XCTAssertEqual(r.accountId, "a1")   // modal
        XCTAssertEqual(r.categoryId, "ent")
    }

    func test_isScheduled_whenTemplateNameMatchesMerchant() {
        let txns = [
            exp("1", "Spotify", -11.99, "2026-03-03"),
            exp("2", "Spotify", -11.99, "2026-04-03"),
            exp("3", "Spotify", -11.99, "2026-05-03"),
            exp("4", "Spotify", -11.99, "2026-06-03"),
        ]
        let tmpl = ScheduledTemplate(id: "t1", name: "Spotify", description: nil, type: "expense",
            amount: 11.99, frequency: "monthly", dayOfMonth: 3, weekDay: nil, accountId: "a1",
            fromAccountId: nil, categoryId: nil, startDate: "2026-03-03", endDate: nil,
            nextRun: "2026-07-03", maxExecutions: nil, installmentTotal: nil, installmentPaid: nil, color: nil)
        let out = Selectors.detectRecurring(txns, "l1", "2026-06-20", [tmpl])
        XCTAssertTrue(out[0].isScheduled)
    }
```
(Existing tests keep calling `detectRecurring(txns, "l1", today)` — the new `scheduled` param defaults to `[]`, and the new `RecurringCharge` init args are filled by the selector, so the existing tests still compile/pass.)

Run: `cd ios/FinchCore && swift test --filter DetectRecurringTests 2>&1 | tail -15` → FAIL (init arity / extra param / `ScheduledTemplate` ctor used).

- [ ] **Step 3: Update `detectRecurring` + add `mode`**

In `Selectors.swift`, replace the whole `detectRecurring(...)` function with:

```swift
    public static func detectRecurring(_ txns: [Tx], _ ledgerId: String, _ today: String,
                                       _ scheduled: [ScheduledTemplate] = [],
                                       minOccurrences: Int = 3) -> [RecurringCharge] {
        let scheduledNames = Set(scheduled.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
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
            guard variance.squareRoot() / mean < 0.35 else { continue }

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
            guard sinceLast <= Int(1.6 * Double(med)) else { continue }

            let mname = (names[key] ?? key).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isScheduled = items.contains { ($0.sourceTemplateId?.isEmpty == false) } || scheduledNames.contains(mname)
            out.append(RecurringCharge(
                id: key, merchantName: names[key] ?? key, averageAmount: r2(mean), cadence: cadence,
                monthlyEstimate: r2(monthlyFor(mean, cadence)), occurrences: items.count,
                lastDate: lastDate, nextEstimatedDate: ymd(addDays(date(lastDate), med)), isScheduled: isScheduled,
                accountId: mode(items.map { $0.account }), categoryId: mode(items.compactMap { $0.category })))
        }
        return out.sorted { $0.monthlyEstimate > $1.monthlyEstimate }
    }

    private static func mode(_ xs: [String]) -> String? {
        guard !xs.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for x in xs { counts[x, default: 0] += 1 }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
    }
```

- [ ] **Step 4: Run filtered + full suite**

```bash
cd ios/FinchCore && swift test --filter DetectRecurringTests 2>&1 | tail -12
swift test 2>&1 | tail -8
```
Expected: all `DetectRecurringTests` pass; full suite + ParityTests green.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Project/Models.swift \
        ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/DetectRecurringTests.swift
git commit -m "feat(ios): detectRecurring — modal account/category + name-match isScheduled"
```

---

### Task 2: UI — prefill init + tappable detected rows

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift`

- [ ] **Step 1: Add the prefill init to `ScheduledSheet`**

After the existing `init(template:prefillStart:)`, add:

```swift
    init(fromCharge c: RecurringCharge) {
        self.template = nil
        _name = State(initialValue: c.merchantName)
        _kind = State(initialValue: .expense)
        _amount = State(initialValue: String(format: "%g", c.averageAmount))
        _accountId = State(initialValue: c.accountId ?? "")
        _fromAccountId = State(initialValue: "")
        _categoryId = State(initialValue: c.categoryId ?? "")
        _frequency = State(initialValue: c.cadence)
        _dayOfMonth = State(initialValue: Int(c.nextEstimatedDate.split(separator: "-").last ?? "1") ?? 1)
        _startDate = State(initialValue: AppDate.isoDay.date(from: c.nextEstimatedDate) ?? Date())
        _installmentEnabled = State(initialValue: false)
        _installmentTotal = State(initialValue: "")
    }
```

- [ ] **Step 2: `ScheduledTab` — pass templates + add the sheet state**

Update the `detected` computed to pass `store.scheduled`:

```swift
    private var detected: [RecurringCharge] {
        Selectors.detectRecurring(store.txns, store.activeLedgerId, store.today, store.scheduled).filter { !$0.isScheduled }
    }
```
Add state near the others (e.g. by `addPrefill`):

```swift
    @State private var addFromCharge: RecurringCharge?
```
Add the sheet (next to the existing `.sheet(...)` modifiers):

```swift
            .sheet(item: $addFromCharge) { ScheduledSheet(fromCharge: $0) }
```

- [ ] **Step 3: Make the detected rows tappable**

In the `ForEach(detected) { r in … }`, wrap the row's `HStack { … }` in a Button:

```swift
                                        ForEach(detected) { r in
                                            Button { addFromCharge = r } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(r.merchantName)
                                                        Text("\(r.cadence.capitalized) · next ~\(r.nextEstimatedDate)")
                                                            .font(.caption).foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Text(store.displayMoneyBase(r.averageAmount)).fontWeight(.medium)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
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
git add ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift
git commit -m "feat(ios): tap a detected recurring charge → prefilled Scheduled sheet"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + seed a monthly merchant** (4 equal monthly expenses, last within the cadence). Build to a **known** derivedDataPath and install that exact product (avoid stale builds):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ats-dd >/dev/null 2>&1
xcrun simctl install "$SIM" /tmp/ats-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
# seed 4 monthly "Netflix" expenses (entry + 2 balanced postings each; exchange_rate=1) into the live DB,
# then: xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab scheduled
```

- [ ] **Step 2: Verify**
  - Scheduled tab → "Detected · not scheduled" → **tap** the Netflix row → `ScheduledSheet`
    opens pre-filled (Name Netflix, amount, Frequency Monthly, an account selected).
  - **Save** → the detected row disappears and a "Netflix" template appears in the scheduled list.
  - Screenshot evidence to `/tmp/add-scheduled.png`. Clean up the seed + `/tmp/ats-dd` after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: struct fields (T1 S1) + tests (T1 S2/S4) + selector/mode/name-match (T1 S3); prefill init (T2 S1), tappable rows + sheet (T2 S2/S3), build (T2 S4), manual (T3). ✓
- Type consistency: `detectRecurring(_:_:_:_:minOccurrences:)`, `RecurringCharge(... accountId: categoryId:)`, `ScheduledSheet(fromCharge:)`, `addFromCharge` consistent. ✓
- Additive selector + `RecurringCharge` is `Identifiable` for `.sheet(item:)`. ParityTests unaffected. ✓
