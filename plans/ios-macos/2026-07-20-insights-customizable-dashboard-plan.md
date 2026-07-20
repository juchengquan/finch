# Insights customizable dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Insights → Trends into a data-driven, customizable dashboard: a card registry rendered from a saved layout, seeded by named templates and editable via a Customize sheet.

**Architecture:** A card registry (`InsightsCatalog`) + `InsightsTemplate` presets + a per-device `InsightsLayout` (`@AppStorage`, JSON). The Trends view renders the layout's ids through the catalog. Breakdown mode is untouched.

**Tech Stack:** Swift / SwiftUI.

## Global Constraints

- **UI/state only.** No engine, projection, or `frontend/` changes; no new selectors (cards keep their current selectors).
- Layout is **per-device, global**, `UserDefaults` via `@AppStorage("finch.insights.layout")` — never DB/synced (matches the app's view-pref convention).
- Card ids are **stable strings** (persisted); the catalog is the single source of truth.
- **Default (unset) layout = the `overview` template.**
- Design doc: `plans/ios-macos/2026-07-20-insights-customizable-dashboard-design.md`.

---

## Phase 1 — registry + templates + persistence + template-switching dashboard

### Task 1: `InsightsTemplate` + `InsightsLayout` (+ unit tests)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsLayout.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/InsightsLayoutTests.swift`

**Interfaces:**
- Produces: `InsightsTemplate` (`.overview/.spending/.wealth/.everything`, `.title`, `.cardIDs`), `InsightsLayout` (`order: [String]`, `templateName: String?`; `RawRepresentable` for `@AppStorage`; `.default`; `matchingTemplate(in:)`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import FinchApp

final class InsightsLayoutTests: XCTestCase {
    func test_defaultLayout_isOverview() {
        XCTAssertEqual(InsightsLayout.default.order, InsightsTemplate.overview.cardIDs)
        XCTAssertEqual(InsightsLayout.default.templateName, InsightsTemplate.overview.rawValue)
    }

    func test_everyTemplateID_existsInCatalog() {
        let catalog = Set(InsightsCatalog.all.map(\.id))
        for t in InsightsTemplate.allCases {
            for id in t.cardIDs { XCTAssertTrue(catalog.contains(id), "\(t.rawValue): unknown id \(id)") }
        }
    }

    func test_catalogIDs_areUnique() {
        let ids = InsightsCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_rawRepresentable_roundTrips() {
        let l = InsightsLayout(order: ["netWorth", "cashflow"], templateName: nil)
        XCTAssertEqual(InsightsLayout(rawValue: l.rawValue), l)
    }

    func test_matchingTemplate_detectsPresetVsCustom() {
        let wealth = InsightsLayout(order: InsightsTemplate.wealth.cardIDs, templateName: nil)
        XCTAssertEqual(wealth.matchingTemplate(), .wealth)
        let custom = InsightsLayout(order: ["netWorth"], templateName: nil)
        XCTAssertNil(custom.matchingTemplate())
    }
}
```

> `test_everyTemplateID_existsInCatalog` / `test_catalogIDs_areUnique` depend on `InsightsCatalog` (Task 2). If Task 2 isn't done yet, expect those two to fail to compile — that's fine; they pass once Task 2 lands. Run `-only-testing` for the two layout-only tests first.

- [ ] **Step 2: Implement**

`InsightsLayout.swift`:

```swift
import Foundation

/// Named preset card sets for the Insights dashboard. "Custom" is NOT a case —
/// it's the derived state when a layout matches no template (see
/// `InsightsLayout.matchingTemplate`).
enum InsightsTemplate: String, CaseIterable, Identifiable {
    case overview, spending, wealth, everything
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .spending: return "Spending"
        case .wealth: return "Wealth"
        case .everything: return "Everything"
        }
    }

    var cardIDs: [String] {
        switch self {
        case .overview:   return ["tips", "monthlySpending", "savingsRate", "netWorth", "categoryBreakdown", "forecast"]
        case .spending:   return ["monthlySpending", "categoryBreakdown", "topMerchants", "categoryDeltas", "spendingHeatmap"]
        case .wealth:     return ["netWorth", "netWorthByType", "cashflow", "savingsRate", "whatIf"]
        case .everything: return InsightsCatalog.all.map(\.id)
        }
    }
}

/// The persisted dashboard layout: enabled card ids in display order, plus the
/// template it currently matches (nil == "Custom"). `RawRepresentable` so it can
/// live in `@AppStorage` as a JSON string.
struct InsightsLayout: Codable, Equatable, RawRepresentable {
    var order: [String]
    var templateName: String?

    static let `default` = InsightsLayout(
        order: InsightsTemplate.overview.cardIDs,
        templateName: InsightsTemplate.overview.rawValue)

    /// The template whose `cardIDs` equal `order` exactly, else nil ("Custom").
    func matchingTemplate() -> InsightsTemplate? {
        InsightsTemplate.allCases.first { $0.cardIDs == order }
    }

    init(order: [String], templateName: String?) {
        self.order = order; self.templateName = templateName
    }

    // MARK: RawRepresentable (JSON) for @AppStorage
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let v = try? JSONDecoder().decode(InsightsLayout.self, from: data) else { return nil }
        self = v
    }
    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
```

- [ ] **Step 3: Run the layout-only tests**

`xcodebuild test … -only-testing:FinchAppTests/InsightsLayoutTests/test_defaultLayout_isOverview -only-testing:…/test_rawRepresentable_roundTrips -only-testing:…/test_matchingTemplate_detectsPresetVsCustom` → PASS. (The two catalog tests compile+pass after Task 2.)

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsLayout.swift ios/FinchApp/Tests/FinchAppTests/InsightsLayoutTests.swift
git commit -m "feat(ios): Insights template + layout model (+ tests)"
```

---

### Task 2: Card registry — move cards out, drop duplicates, add `InsightsCatalog`

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsCards.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`

**Interfaces:**
- Produces: `InsightsCatalog.all: [InsightsCardEntry]`, `InsightsCatalog.entry(_ id:) -> InsightsCardEntry?`.
- Consumes: the existing card structs + the `Card`/`InsightsCard` chrome + `cardPalette`.

- [ ] **Step 1: Move the cards to `InsightsCards.swift`**

Cut from `InsightsTab.swift` into the new `InsightsCards.swift` (with `import SwiftUI` / `import FinchCore`): the `Card` chrome, `cardPalette`, and all card structs, **changing each `private struct XCard`/`private struct Card`/`private let cardPalette` to internal** (drop `private`) so the registry can reference them. **Delete entirely** `RecentExpensesCard` and `HoldingsCard` (duplicate the Activity / Holdings surfaces). Also move `monthLabel`, `ExportedCsv`, and `BreakdownView` if they were private and are still referenced by `InsightsTab` — keep them accessible (internal) but they stay used by the Breakdown mode.

> This is a mechanical relocation — no behavior change to any card. Verify nothing else in the app references `RecentExpensesCard`/`HoldingsCard` (they were InsightsTab-private, so nothing does).

- [ ] **Step 2: Add the registry** (in `InsightsCards.swift`)

```swift
/// One dashboard card in the catalog: a stable id, a title for the Customize
/// list, whether it consumes the 3M/6M/1Y range, and a builder.
struct InsightsCardEntry: Identifiable {
    let id: String
    let title: String
    let consumesRange: Bool
    let make: (_ rangeMonths: Int) -> AnyView
}

/// The single source of truth for the dashboard's cards, in default order.
enum InsightsCatalog {
    static let all: [InsightsCardEntry] = [
        .init(id: "tips",              title: "Insights",           consumesRange: false, make: { _ in AnyView(InsightsCard()) }),
        .init(id: "monthlySpending",   title: "Monthly spending",   consumesRange: true,  make: { AnyView(MonthlySpendingCard(months: $0)) }),
        .init(id: "netWorth",          title: "Net worth",          consumesRange: true,  make: { AnyView(NetWorthCard(months: $0)) }),
        .init(id: "cashflow",          title: "Cashflow",           consumesRange: true,  make: { AnyView(CashflowCard(months: $0)) }),
        .init(id: "savingsRate",       title: "Savings rate",       consumesRange: false, make: { _ in AnyView(SavingsRateCard()) }),
        .init(id: "whatIf",            title: "What-if",            consumesRange: false, make: { _ in AnyView(WhatIfCard()) }),
        .init(id: "categoryDeltas",    title: "Category changes",   consumesRange: false, make: { _ in AnyView(CategoryDeltasCard()) }),
        .init(id: "weeklyDigest",      title: "Weekly digest",      consumesRange: false, make: { _ in AnyView(WeeklyDigestCard()) }),
        .init(id: "incomeSankey",      title: "Income flow",        consumesRange: false, make: { _ in AnyView(IncomeSankeyCard()) }),
        .init(id: "spendingHeatmap",   title: "Spending heatmap",   consumesRange: false, make: { _ in AnyView(SpendingHeatmapCard()) }),
        .init(id: "netWorthByType",    title: "Net worth by type",  consumesRange: false, make: { _ in AnyView(NetWorthByTypeCard()) }),
        .init(id: "categoryBreakdown", title: "Category breakdown", consumesRange: false, make: { _ in AnyView(CategoryBreakdownCard()) }),
        .init(id: "topMerchants",      title: "Top merchants",      consumesRange: false, make: { _ in AnyView(TopMerchantsCard()) }),
        .init(id: "forecast",          title: "Forecast",           consumesRange: false, make: { _ in AnyView(ForecastCard()) }),
    ]
    static func entry(_ id: String) -> InsightsCardEntry? { all.first { $0.id == id } }
}
```

> Confirm the exact card struct names + that `MonthlySpendingCard`/`NetWorthCard`/`CashflowCard` accept `months:` (memberwise `var months = 6`) — matching the current call sites in `InsightsTab`.

- [ ] **Step 3: Build both platforms**

`xcodegen generate`; iOS + FinchMac `build` → `BUILD SUCCEEDED`. Then run the full `InsightsLayoutTests` (the two catalog tests now compile) → PASS.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsCards.swift ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): Insights card registry; move cards out; drop RecentExpenses+Holdings"
```

---

### Task 3: Render Trends from the layout + template menu

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`

- [ ] **Step 1: Add the persisted layout + render loop**

In `InsightsTab`, add:
```swift
    @AppStorage("finch.insights.layout") private var layout = InsightsLayout.default
```
Replace the hardcoded Trends card list (the `if view == .trends { … InsightsCard(); MonthlySpendingCard(months:) … }` block down to `HoldingsCard()`) with a dynamic render over the layout, keeping the range picker:

```swift
                            if view == .trends {
                                Picker("Range", selection: $rangeMonths) {
                                    Text("3M").tag(3); Text("6M").tag(6); Text("1Y").tag(12)
                                }
                                .pickerStyle(.segmented)
                                ForEach(layout.order, id: \.self) { id in
                                    if let entry = InsightsCatalog.entry(id) {
                                        entry.make(rangeMonths)
                                    }
                                }
                            } else {
                                BreakdownView()
                            }
```
(Unknown ids are skipped by the `if let`.)

- [ ] **Step 2: Add the template menu** (in the Trends header area, next to / above the range picker)

```swift
                            if view == .trends {
                                Menu {
                                    ForEach(InsightsTemplate.allCases) { t in
                                        Button(t.title) { layout = InsightsLayout(order: t.cardIDs, templateName: t.rawValue) }
                                    }
                                } label: {
                                    let name = layout.matchingTemplate()?.title ?? "Custom"
                                    Label(name, systemImage: "square.grid.2x2")
                                        .font(.subheadline)
                                }
                            }
```
(Placement: put this Menu directly under the `[Trends | Breakdown]` picker, before the Range picker. The "Customize…" entry is added in Phase 2.)

- [ ] **Step 3: Build both platforms** → `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): render Insights Trends from saved layout + template menu"
```

---

## Phase 2 — the Customize sheet

### Task 4: `InsightsCustomizeSheet` (show/hide + reorder) + "Customize…" entry

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsCustomizeSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`

- [ ] **Step 1: The sheet**

```swift
import SwiftUI

/// Show/hide + reorder the dashboard cards. Enabled cards (in `layout.order`)
/// appear first, reorderable; disabled cards follow. Any edit that no longer
/// matches a template clears `templateName` ("Custom").
struct InsightsCustomizeSheet: View {
    @Binding var layout: InsightsLayout
    @Environment(\.dismiss) private var dismiss

    private var enabled: [String] { layout.order }
    private var disabled: [String] { InsightsCatalog.all.map(\.id).filter { !layout.order.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Shown") {
                    ForEach(enabled, id: \.self) { id in
                        row(id, on: true)
                    }
                    .onMove { from, to in
                        layout.order.move(fromOffsets: from, toOffset: to)
                        retag()
                    }
                }
                if !disabled.isEmpty {
                    Section("Hidden") {
                        ForEach(disabled, id: \.self) { id in row(id, on: false) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))   // drag handles always visible
            .navigationTitle("Customize")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Done").confirmCheckmarkStyle()
                }
            }
        }
    }

    @ViewBuilder private func row(_ id: String, on: Bool) -> some View {
        HStack {
            Text(InsightsCatalog.entry(id)?.title ?? id)
            Spacer()
            Toggle("", isOn: Binding(
                get: { layout.order.contains(id) },
                set: { isOn in
                    if isOn { if !layout.order.contains(id) { layout.order.append(id) } }
                    else { layout.order.removeAll { $0 == id } }
                    retag()
                }))
            .labelsHidden()
        }
    }

    /// Recompute whether the current order matches a template.
    private func retag() { layout.templateName = layout.matchingTemplate()?.rawValue }
}
```

> Reuse `confirmCheckmarkStyle()` (Common/ViewModifiers). Toggling a hidden card **on** appends it to the end of `order`; toggling **off** removes it. Reordering only applies within the enabled ("Shown") section.

- [ ] **Step 2: Present it from the template menu**

In `InsightsTab`, add `@State private var customizing = false`, add a `Divider()` + `Button("Customize…") { customizing = true }` to the template `Menu`, and:
```swift
                            .sheet(isPresented: $customizing) {
                                InsightsCustomizeSheet(layout: $layout)
                                    #if os(iOS)
                                    .presentationDetents([.large])
                                    .presentationDragIndicator(.visible)
                                    #endif
                            }
```

- [ ] **Step 3: Build both platforms** → `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsCustomizeSheet.swift ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): Insights Customize sheet (show/hide + reorder)"
```

---

## Manual verification (PR body)

1. Fresh install → Trends shows the **Overview** set; menu reads "Overview".
2. Menu → Spending / Wealth / Everything → the card set + order change; menu label follows.
3. Customize → toggle a card off / on, drag to reorder → menu flips to "Custom"; persists across relaunch.
4. Range 3M/6M/1Y still drives Monthly spending / Net worth / Cashflow.
5. Breakdown mode unchanged (per-category monthly + CSV/PDF export).
6. RecentExpenses + Holdings no longer appear anywhere in Insights. macOS builds + works.

## Self-Review

- **Spec coverage:** registry (T2), templates + layout + persistence (T1), render-from-layout + template menu (T3), Customize sheet + "Custom" (T4); drops the 2 duplicates (T2); Breakdown untouched; global per-device `@AppStorage`; default overview. ✓
- **Type consistency:** `InsightsLayout(order:templateName:)`, `matchingTemplate()`, `InsightsCatalog.all/.entry`, `InsightsCardEntry.make(_:)`, `InsightsTemplate.cardIDs/.title` used identically across tasks. ✓
- **Placeholders:** the card-move (T2 S1) is a described relocation, not pasted verbatim (mechanical, no behavior change); all new logic has complete code. ✓
