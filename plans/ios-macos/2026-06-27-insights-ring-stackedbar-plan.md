# Wire Ring + StackedBar into Insights — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Savings rate" `Ring` card and an asset-allocation `StackedBar` (inside the existing "Net worth by type" card) to the Insights tab.

**Architecture:** Two self-contained additions to `Tabs/InsightsTab.swift`, each a private SwiftUI card reusing an existing selector (`monthlyCashflow`, `netWorthByAccountType`). No `FinchCore`/selector changes; savings-rate math is inline. Verified by iOS + macOS build + a simulator visual check (no unit tests — consistent with the other 13 cards).

**Tech Stack:** Swift / SwiftUI; XcodeGen project in `ios/`. Spec: `plans/ios-macos/2026-06-27-insights-ring-stackedbar-spec.md`.

## Global Constraints

- `FinchApp` target only — all edits in `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`. No `FinchCore`/selector changes. No new dependencies.
- Build **both** `FinchApp` (iOS) and `FinchMac` (macOS) — the cards are cross-platform SwiftUI; introduce no iOS-only APIs.
- iOS has **no** `Color.success`/`.warning` tokens — use standard `.green`/`.orange`.
- Per-type color palette (verbatim): `cash → .green`, `savings → .blue`, `investment → .purple`, `fx → .teal`, `virtual → .gray`, default → `.secondary`.
- Run build/sim from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` first. Use a booted iPhone sim (e.g. `finch-fresh-5`, or boot one). See the `ios-build-launch` skill for exact commands.
- Don't change the other 11 cards, the chart primitives, or the Insights range/segmented control.

---

### Task 1: "Savings rate" Ring card

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift` (add a private `SavingsRateCard` struct; insert it in the card stack after `CashflowCard`)

**Interfaces:**
- Consumes (existing): `Selectors.monthlyCashflow(_ txns:_ ledgerId:_ endMonth:_ n:) -> [CashflowPoint]` where `CashflowPoint` has `.inc: Double` and `.exp: Double` (expense stored positive); `Card(title:) { content }`; `Ring(value:max:color:) { label }`.
- Produces: `private struct SavingsRateCard: View` (used only in this file's stack).

- [ ] **Step 1: Add the `SavingsRateCard` struct**

Add this struct in `InsightsTab.swift` (next to the other private card structs, e.g. just after `CashflowCard`'s definition):

```swift
/// This month's savings rate — (income − expense) ÷ income — as a Ring.
/// Inline math from `monthlyCashflow`; handles no-income and overspent (negative).
private struct SavingsRateCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let pt = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, String(store.today.prefix(7)), 1).last
        let inc = pt?.inc ?? 0
        let exp = pt?.exp ?? 0
        let rate: Double? = inc > 0 ? (inc - exp) / inc : nil
        Card(title: "Savings rate") {
            if let rate {
                let pct = Int((rate * 100).rounded())
                HStack(spacing: 16) {
                    Ring(value: Swift.max(0, rate * 100), max: 100,
                         color: rate >= 0 ? .green : .orange) {
                        Text("\(pct)%").font(.caption).fontWeight(.semibold)
                    }
                    Text(rate >= 0 ? "of income saved this month"
                                   : "spent more than earned this month")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No income this month").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: Insert the card into the stack (after `CashflowCard`)**

In the card stack, change:
```swift
                                CashflowCard(months: rangeMonths)
                                CategoryDeltasCard()
```
to:
```swift
                                CashflowCard(months: rangeMonths)
                                SavingsRateCard()
                                CategoryDeltasCard()
```

- [ ] **Step 3: Build iOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`. (If the named device isn't found, use a booted sim's `id=<udid>`.)

- [ ] **Step 4: Build macOS**

```bash
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): Insights — Savings rate Ring card"
```

---

### Task 2: Asset-allocation StackedBar in "Net worth by type"

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift` (`NetWorthByTypeCard` body + a private `typeColor` helper)

**Interfaces:**
- Consumes (existing): `Selectors.netWorthByAccountType(_ accounts:_ ledgerId:_ toBase:)` → rows with `.type: String` and `.balance: Double`; `StackedBar(slices: [StackedBar.Slice])`, `StackedBar.Slice(value: Double, color: Color)`; `AccountSheetTypeLabel.label(_:)`.

- [ ] **Step 1: Replace the `NetWorthByTypeCard` struct**

Replace the existing `NetWorthByTypeCard` struct with this (adds the StackedBar above the list when there are positive-balance asset types, plus the `typeColor` helper):

```swift
private struct NetWorthByTypeCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let rows = Selectors.netWorthByAccountType(store.accounts, store.activeLedgerId) { store.toBase($0, from: $1) }
            .filter { $0.balance != 0 }
        let assets = rows.filter { $0.balance > 0 }
        Card(title: "Net worth by type") {
            if rows.isEmpty {
                Text("No accounts").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    if !assets.isEmpty {
                        StackedBar(slices: assets.map {
                            StackedBar.Slice(value: $0.balance, color: typeColor($0.type))
                        })
                        .padding(.bottom, 4)
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(AccountSheetTypeLabel.label(r.type))
                            Spacer()
                            Text(store.displayMoneyBase(r.balance)).fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "cash":       return .green
        case "savings":    return .blue
        case "investment": return .purple
        case "fx":         return .teal
        case "virtual":    return .gray
        default:           return .secondary
        }
    }
}
```

- [ ] **Step 2: Build iOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Build macOS**

```bash
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full FinchAppTests (regression — no logic changed, should stay green)**

```bash
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -only-testing:FinchAppTests 2>&1 | grep -iE "Executed .* tests|TEST SUCCEEDED|TEST FAILED|error:"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Verify on the simulator**

Install + launch (see the `ios-build-launch` skill), open **Insights**, and confirm by eye:
- **Savings rate** card renders a ring with the center % and the caption; on the seeded demo data it shows a positive % (or, if the demo month has no income, the "No income this month" caption — both are valid).
- **Net worth by type** shows a proportional `StackedBar` above the type list (segments colored per the palette); the list rows are unchanged.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): Insights — asset-allocation StackedBar in Net-worth-by-type"
```

---

## Self-Review

**1. Spec coverage:**
- Savings-rate Ring card (inline `(inc−exp)/inc`, no-income + overspent states, `.green`/`.orange`) → Task 1. ✅
- StackedBar asset allocation in `NetWorthByTypeCard` (assets only, `typeColor` palette, list unchanged, no-asset → list only) → Task 2. ✅
- FinchApp-only / no FinchCore / no new selectors → both tasks stay in `InsightsTab.swift`. ✅
- Build iOS + macOS, sim visual check, no new unit tests → Task 1 Steps 3-4; Task 2 Steps 2-5. ✅
- Other cards / primitives untouched → only `SavingsRateCard` added + `NetWorthByTypeCard` changed. ✅

**2. Placeholder scan:** none — both code steps show complete structs; commands have expected output.

**3. Type consistency:** `SavingsRateCard`, `NetWorthByTypeCard`, `typeColor(_:)`, `CashflowPoint.inc/.exp`, `StackedBar.Slice(value:color:)`, `Ring(value:max:color:){label}` used consistently with the spec and the existing code read from the file. `Swift.max` is used to avoid colliding with `Ring`'s `max:` label.
