# Widgets CP2 (configurable Account + Budget widgets) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin a chosen account's balance or a chosen budget's progress via configurable widgets.

**Architecture:** Expand `WidgetSnapshot` (FinchCore) with optional per-account / per-budget arrays + fill them in the app writer; add two `AppIntentConfiguration` widgets in `FinchWidget` whose pickers read the snapshot (the extension can't reach the DB). No engine/DB/App-Group change.

**Tech Stack:** SwiftUI + WidgetKit + AppIntents (iOS 17), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No engine/DB/App-Group change.** New snapshot arrays are **optional** (`[…]?`), so old snapshots decode (synthesized Codable). Consumers use `?? []`. Account balance is the account's **native** value/currency, formatted with `Money.format(_:currency:)` (FinchCore).
- Config intents + snapshot-backed `EntityQuery` live **in `FinchWidget/`** (`import AppIntents`; no project.yml/FinchCore change). FinchOverview widget (CP1) stays unchanged.
- **Must build iOS AND macOS (FinchMac).** The `FinchApp` build embeds + compiles `FinchWidget`. `xcodegen generate` first. FinchApp tests via `xcodebuild test -only-testing:FinchAppTests`; FinchCore via `swift test`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):** `ios/FinchCore/Sources/FinchCore/Project/WidgetSnapshot.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/Widgets/WidgetSnapshot.swift`.
**Test:** `ios/FinchApp/Tests/FinchAppTests/WidgetSnapshotTests.swift` (extend).
**Create (widget):** `ios/FinchWidget/WidgetIntents.swift`.
**Modify (widget):** `ios/FinchWidget/FinchWidget.swift` (add the two widgets + bundle).

---

### Task 1: Snapshot expansion (per-account / per-budget) + writer + tests

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/WidgetSnapshot.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Widgets/WidgetSnapshot.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Produces: `AccountSnapshotItem {id,name,balance,currency}`, `BudgetSnapshotItem {id,name,usedPct}`; `WidgetSnapshot.accounts: [AccountSnapshotItem]?`, `.budgets: [BudgetSnapshotItem]?`.

- [ ] **Step 1: Write the failing tests**

Append to `WidgetSnapshotTests.swift`:
```swift
func test_snapshot_carries_accounts_and_budgets() throws {
    let snap = WidgetSnapshot(
        netWorth: 100, currency: "USD", budgetUsedPct: 50, weeklySpent: 20, generatedAt: "t",
        accounts: [AccountSnapshotItem(id: "a1", name: "Checking", balance: 1240, currency: "USD")],
        budgets: [BudgetSnapshotItem(id: "b1", name: "Food", usedPct: 75)])
    let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snap))
    XCTAssertEqual(back.accounts?.map(\.id), ["a1"])
    XCTAssertEqual(back.accounts?.first?.balance, 1240)
    XCTAssertEqual(back.budgets?.first?.usedPct, 75)
}

func test_snapshot_back_compat_old_blob_without_arrays() throws {
    let old = #"{"netWorth":100,"currency":"USD","budgetUsedPct":50,"weeklySpent":20,"generatedAt":"t"}"#
    let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
    XCTAssertNil(snap.accounts)
    XCTAssertNil(snap.budgets)
    XCTAssertEqual(snap.netWorth, 100)
}
```

- [ ] **Step 2: Run to verify failure**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/WidgetSnapshotTests 2>&1 | grep -iE "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL — `AccountSnapshotItem`/`BudgetSnapshotItem` undefined; `WidgetSnapshot` has no `accounts`/`budgets`.

- [ ] **Step 3: Expand `WidgetSnapshot`**

In `WidgetSnapshot.swift`, add the two item structs (above `WidgetSnapshot`):
```swift
public struct AccountSnapshotItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let balance: Double
    public let currency: String
    public init(id: String, name: String, balance: Double, currency: String) {
        self.id = id; self.name = name; self.balance = balance; self.currency = currency
    }
}

public struct BudgetSnapshotItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let usedPct: Int
    public init(id: String, name: String, usedPct: Int) {
        self.id = id; self.name = name; self.usedPct = usedPct
    }
}
```
Add the two stored properties to `WidgetSnapshot` (after `generatedAt`):
```swift
    public var accounts: [AccountSnapshotItem]?
    public var budgets: [BudgetSnapshotItem]?
```
Extend the memberwise `init` (append, defaulted so existing callers compile):
```swift
    public init(netWorth: Double, currency: String, budgetUsedPct: Int, weeklySpent: Double, generatedAt: String,
                accounts: [AccountSnapshotItem]? = nil, budgets: [BudgetSnapshotItem]? = nil) {
        self.netWorth = netWorth; self.currency = currency
        self.budgetUsedPct = budgetUsedPct; self.weeklySpent = weeklySpent; self.generatedAt = generatedAt
        self.accounts = accounts; self.budgets = budgets
    }
```

- [ ] **Step 4: Fill the arrays in the writer**

In `FinchApp/.../Widgets/WidgetSnapshot.swift` `build(from:)`, before the `return`, add:
```swift
        let accts = store.accounts.map {
            AccountSnapshotItem(id: $0.id, name: $0.name ?? "Account", balance: $0.balance, currency: $0.currency ?? store.displayCurrency)
        }
        let buds = store.budgets.map {
            BudgetSnapshotItem(id: $0.id, name: $0.name, usedPct: Selectors.budgetProgress($0, store.txns, store.today, store.categoryNodes).pct)
        }
```
and change the `return` to pass them:
```swift
        return WidgetSnapshot(netWorth: nw, currency: store.displayCurrency,
                              budgetUsedPct: pct, weeklySpent: weekly, generatedAt: stamp,
                              accounts: accts, budgets: buds)
```

- [ ] **Step 5: Run the tests**

Run (same as Step 2). Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Full FinchCore + macOS build**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: FinchCore all pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Project/WidgetSnapshot.swift \
        ios/FinchApp/Sources/FinchApp/Widgets/WidgetSnapshot.swift \
        ios/FinchApp/Tests/FinchAppTests/WidgetSnapshotTests.swift
git commit -m "feat(ios): widget snapshot — per-account balances + per-budget usage"
```

---

### Task 2: Configurable Account widget

**Files:**
- Create: `ios/FinchWidget/WidgetIntents.swift`
- Modify: `ios/FinchWidget/FinchWidget.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot.accounts` (Task 1), `AppGroup.readWidgetSnapshot()`, `Money.format(_:currency:)`.
- Produces: `WidgetAccountEntity`/`WidgetAccountQuery`/`SelectAccountIntent`; `AccountWidget`.

- [ ] **Step 1: Create `WidgetIntents.swift` (account)**

Create `ios/FinchWidget/WidgetIntents.swift`:
```swift
import AppIntents
import FinchCore

struct WidgetAccountEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Account" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = WidgetAccountQuery()
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        items().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetAccountEntity] { items() }
    private func items() -> [WidgetAccountEntity] {
        (AppGroup.readWidgetSnapshot()?.accounts ?? []).map { WidgetAccountEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectAccountIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Account" }
    static var description: IntentDescription { IntentDescription("Choose which account this widget shows.") }
    @Parameter(title: "Account") var account: WidgetAccountEntity?
    init() {}
}
```

- [ ] **Step 2: Add `AccountWidget` to `FinchWidget.swift`**

Add (e.g. after `FinchWidget`):
```swift
struct AccountEntry: TimelineEntry {
    let date: Date
    let item: AccountSnapshotItem?
}

struct AccountProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AccountEntry { AccountEntry(date: Date(), item: nil) }
    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> AccountEntry { entry(configuration) }
    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<AccountEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }
    private func entry(_ c: SelectAccountIntent) -> AccountEntry {
        let snap = AppGroup.readWidgetSnapshot()
        let item = snap?.accounts?.first { $0.id == c.account?.id } ?? snap?.accounts?.first
        return AccountEntry(date: Date(), item: item)
    }
}

struct AccountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AccountEntry
    var body: some View {
        if let item = entry.item {
            let amount = Money.format(item.balance, currency: item.currency)
            switch family {
            case .accessoryInline:
                Text("\(item.name) · \(amount)").containerBackground(.clear, for: .widget)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.caption2).foregroundStyle(.secondary)
                    Text(amount).font(.headline).minimumScaleFactor(0.6).widgetAccentable()
                }.containerBackground(.clear, for: .widget)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.caption).foregroundStyle(.secondary)
                    Text(amount).font(.title3).fontWeight(.semibold).minimumScaleFactor(0.6)
                }.padding().containerBackground(.fill.tertiary, for: .widget)
            }
        } else {
            Text("Pick an account").font(.caption).foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct AccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FinchAccount", intent: SelectAccountIntent.self, provider: AccountProvider()) { entry in
            AccountWidgetView(entry: entry)
        }
        .configurationDisplayName("finch account")
        .description("A chosen account's balance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
```
Add `AccountWidget()` to the bundle:
```swift
@main
struct FinchWidgetBundle: WidgetBundle {
    var body: some Widget { FinchWidget(); AccountWidget() }
}
```

- [ ] **Step 3: Build iOS + macOS**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchWidget/WidgetIntents.swift ios/FinchWidget/FinchWidget.swift
git commit -m "feat(ios): configurable Account widget (pick an account → balance)"
```

---

### Task 3: Configurable Budget widget

**Files:**
- Modify: `ios/FinchWidget/WidgetIntents.swift`
- Modify: `ios/FinchWidget/FinchWidget.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot.budgets` (Task 1); produces `WidgetBudgetEntity`/`WidgetBudgetQuery`/`SelectBudgetIntent`; `BudgetWidget`.

- [ ] **Step 1: Add the budget intent to `WidgetIntents.swift`**

Append:
```swift
struct WidgetBudgetEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Budget" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = WidgetBudgetQuery()
}

struct WidgetBudgetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetBudgetEntity] {
        items().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetBudgetEntity] { items() }
    private func items() -> [WidgetBudgetEntity] {
        (AppGroup.readWidgetSnapshot()?.budgets ?? []).map { WidgetBudgetEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectBudgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Budget" }
    static var description: IntentDescription { IntentDescription("Choose which budget this widget shows.") }
    @Parameter(title: "Budget") var budget: WidgetBudgetEntity?
    init() {}
}
```

- [ ] **Step 2: Add `BudgetWidget` to `FinchWidget.swift`**

Add:
```swift
struct BudgetEntry: TimelineEntry {
    let date: Date
    let item: BudgetSnapshotItem?
}

struct BudgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry { BudgetEntry(date: Date(), item: nil) }
    func snapshot(for configuration: SelectBudgetIntent, in context: Context) async -> BudgetEntry { entry(configuration) }
    func timeline(for configuration: SelectBudgetIntent, in context: Context) async -> Timeline<BudgetEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(3600)))
    }
    private func entry(_ c: SelectBudgetIntent) -> BudgetEntry {
        let snap = AppGroup.readWidgetSnapshot()
        let item = snap?.budgets?.first { $0.id == c.budget?.id } ?? snap?.budgets?.first
        return BudgetEntry(date: Date(), item: item)
    }
}

struct BudgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry
    var body: some View {
        if let item = entry.item {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(item.usedPct), in: 0...100) { Text("Budget") } currentValueLabel: { Text("\(item.usedPct)") }
                    .gaugeStyle(.accessoryCircular)
                    .containerBackground(.clear, for: .widget)
            default:
                VStack(spacing: 6) {
                    Text(item.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Gauge(value: Double(item.usedPct), in: 0...100) { Text("Budget") } currentValueLabel: { Text("\(item.usedPct)%") }
                        .gaugeStyle(.accessoryCircularCapacity)
                }.padding().containerBackground(.fill.tertiary, for: .widget)
            }
        } else {
            Text("Pick a budget").font(.caption).foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FinchBudget", intent: SelectBudgetIntent.self, provider: BudgetProvider()) { entry in
            BudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("finch budget")
        .description("A chosen budget's usage.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
```
Add `BudgetWidget()` to the bundle:
```swift
@main
struct FinchWidgetBundle: WidgetBundle {
    var body: some Widget { FinchWidget(); AccountWidget(); BudgetWidget() }
}
```

- [ ] **Step 3: Build iOS + full FinchApp suite + macOS**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** TEST SUCCEEDED **`; `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification on the simulator**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch   # writes the snapshot (accounts + budgets)
```
Home Screen → add widget → **finch account** and **finch budget** appear; long-press → Edit Widget → the Account/Budget picker lists the ledger's accounts/budgets; pick one → the widget shows that account's balance / that budget's ring. Unconfigured shows the first item (or "Pick…" when there are none).

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchWidget/WidgetIntents.swift ios/FinchWidget/FinchWidget.swift
git commit -m "feat(ios): configurable Budget widget (pick a budget → usage ring)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-widgets-cp2-design.md`):
- Snapshot += optional `accounts`/`budgets` (back-compat) + writer fills them + tests (round-trip + old-blob) → Task 1. ✓
- Configurable **Account** widget (snapshot-backed picker, native balance via Money.format, families, placeholder) → Task 2. ✓
- Configurable **Budget** widget (snapshot-backed picker, usage ring, placeholder) → Task 3. ✓
- Intents in `FinchWidget/`; FinchOverview unchanged; no engine/App-Group change; build iOS+macOS → all tasks. ✓

**Placeholder scan:** No TBD/TODO; full code each step; sim step concrete. ✓

**Type consistency:** `AccountSnapshotItem`/`BudgetSnapshotItem` produced in Task 1, consumed in Tasks 2/3; `WidgetSnapshot(...)` init gains defaulted `accounts:/budgets:` (existing call sites compile); `AppGroup.readWidgetSnapshot()?.accounts/budgets` optional-chained `?? []`; `Money.format(_:currency:)` (FinchCore) used in the widget; `AppIntentConfiguration`/`AppIntentTimelineProvider`/`WidgetConfigurationIntent`/`AppEntity`/`EntityQuery` are iOS-17 AppIntents APIs; bundle lists `FinchWidget()` + `AccountWidget()` + `BudgetWidget()`. ✓

---

## Out of scope (CP3 / later)

Interactive quick-add `Button(intent:)` (CP3); the Watch complication (separate sub-project); per-account history/sparkline; combining account+budget into one widget with a type switch.
