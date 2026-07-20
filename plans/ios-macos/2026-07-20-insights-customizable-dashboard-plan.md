# Insights customizable dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Insights → Trends into a data-driven, customizable dashboard: a card registry rendered from a saved layout, seeded by named templates and editable via a Customize sheet.

**Architecture:** A card registry (`InsightsCatalog`) + `InsightsTemplate` presets + a per-device `InsightsLayout` (`@AppStorage`, JSON). The Trends view renders the layout's ids through the catalog. Breakdown mode is untouched.

**Tech Stack:** Swift / SwiftUI.

## Global Constraints

- **UI/state only.** No engine, projection, or `frontend/` changes; no new selectors (cards keep their current selectors).
- Layout is **per-device, global**, `UserDefaults` via `@AppStorage("finch.insights.layout")` — never DB/synced (matches the app's view-pref convention).
- Card ids are **stable strings** (persisted); `InsightsCatalog` is the single source of truth for cards + order.
- **Default (unset) layout = the `overview` template.**
- **Ordering note:** `InsightsTemplate.everything` and the template/catalog tests reference `InsightsCatalog`, so the registry and the template/layout model ship in ONE foundation task (Task 1).
- Design doc: `plans/ios-macos/2026-07-20-insights-customizable-dashboard-design.md`.

---

## Phase 1 → PR #1 (template-switching dashboard)

### Task 1: Foundation — card registry + template/layout model (+ tests)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsCards.swift` (moved cards + registry)
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsLayout.swift` (template + layout)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift` (cards removed from here)
- Test: `ios/FinchApp/Tests/FinchAppTests/InsightsLayoutTests.swift`

**Interfaces (produced for later tasks):**
- `InsightsCardEntry { id, title, consumesRange, make(_ rangeMonths: Int) -> AnyView }`
- `InsightsCatalog.all: [InsightsCardEntry]`, `InsightsCatalog.entry(_ id:) -> InsightsCardEntry?`
- `InsightsTemplate` (`.overview/.spending/.wealth/.everything`, `.title`, `.cardIDs`)
- `InsightsLayout { order: [String], templateName: String? }` (`RawRepresentable`, `.default`, `matchingTemplate()`)

- [ ] **Step 1: Move the cards + add the registry**

Cut from `InsightsTab.swift` into a new `InsightsCards.swift` (`import SwiftUI` / `import FinchCore`): the `Card` chrome, `cardPalette`, `monthLabel`, `ExportedCsv`, `BreakdownView`, and all card structs — changing each `private` to internal (drop `private`) so the registry (and `InsightsTab`) can reference them across files. **Delete entirely** `RecentExpensesCard` and `HoldingsCard` (they duplicate the Activity tab / the Holdings view + Accounts; both were InsightsTab-private, so nothing else references them). No behavior change to any surviving card — a mechanical relocation.

Append the registry to `InsightsCards.swift`:

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

> Confirm the exact surviving card struct names + that `MonthlySpendingCard`/`NetWorthCard`/`CashflowCard` accept `months:` (memberwise `var months = 6`), matching the current `InsightsTab` call sites.

- [ ] **Step 2: Add the template + layout model**

`InsightsLayout.swift`:

```swift
import Foundation

/// Named preset card sets. "Custom" is NOT a case — it's the derived state when
/// a layout matches no template (see `InsightsLayout.matchingTemplate`).
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

    init(order: [String], templateName: String?) { self.order = order; self.templateName = templateName }

    // RawRepresentable (JSON) for @AppStorage
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

- [ ] **Step 3: Write the tests**

`InsightsLayoutTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class InsightsLayoutTests: XCTestCase {
    func test_defaultLayout_isOverview() {
        XCTAssertEqual(InsightsLayout.default.order, InsightsTemplate.overview.cardIDs)
        XCTAssertEqual(InsightsLayout.default.templateName, InsightsTemplate.overview.rawValue)
    }
    func test_catalogIDs_areUnique() {
        let ids = InsightsCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
    func test_everyTemplateID_existsInCatalog() {
        let catalog = Set(InsightsCatalog.all.map(\.id))
        for t in InsightsTemplate.allCases {
            for id in t.cardIDs { XCTAssertTrue(catalog.contains(id), "\(t.rawValue): unknown id \(id)") }
        }
    }
    func test_rawRepresentable_roundTrips() {
        let l = InsightsLayout(order: ["netWorth", "cashflow"], templateName: nil)
        XCTAssertEqual(InsightsLayout(rawValue: l.rawValue), l)
    }
    func test_matchingTemplate_detectsPresetVsCustom() {
        XCTAssertEqual(InsightsLayout(order: InsightsTemplate.wealth.cardIDs, templateName: nil).matchingTemplate(), .wealth)
        XCTAssertNil(InsightsLayout(order: ["netWorth"], templateName: nil).matchingTemplate())
    }
}
```

- [ ] **Step 4: Build + test**

`xcodegen generate`; iOS + FinchMac `build` → `BUILD SUCCEEDED`; `xcodebuild test … -only-testing:FinchAppTests/InsightsLayoutTests` → 5/5 PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsCards.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/Insights/InsightsLayout.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift \
        ios/FinchApp/Tests/FinchAppTests/InsightsLayoutTests.swift
git commit -m "feat(ios): Insights card registry + template/layout model (+tests); drop RecentExpenses+Holdings"
```

---

### Task 2: Render Trends from the layout + template menu

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`

**Interfaces:** Consumes `InsightsLayout`, `InsightsTemplate`, `InsightsCatalog` (Task 1).

- [ ] **Step 1: Persisted layout + template menu + render loop**

Add to `InsightsTab`:
```swift
    @AppStorage("finch.insights.layout") private var layout = InsightsLayout.default
```

Replace the hardcoded Trends block (from `InsightsCard()` down through `if !store.holdings.isEmpty { HoldingsCard() }`) with the template menu + range picker + a render loop over the layout:

```swift
                            if view == .trends {
                                Menu {
                                    ForEach(InsightsTemplate.allCases) { t in
                                        Button(t.title) { layout = InsightsLayout(order: t.cardIDs, templateName: t.rawValue) }
                                    }
                                } label: {
                                    Label(layout.matchingTemplate()?.title ?? "Custom", systemImage: "square.grid.2x2")
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
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

- [ ] **Step 2: Build both platforms** → `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): render Insights Trends from saved layout + template menu"
```

---

## Phase 2 → PR #2 (Customize sheet) — implement after PR #1 merges

### Task 3: `InsightsCustomizeSheet` (show/hide + reorder) + "Customize…" entry

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

    private var disabled: [String] { InsightsCatalog.all.map(\.id).filter { !layout.order.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Shown") {
                    ForEach(layout.order, id: \.self) { id in row(id) }
                        .onMove { from, to in layout.order.move(fromOffsets: from, toOffset: to); retag() }
                }
                if !disabled.isEmpty {
                    Section("Hidden") { ForEach(disabled, id: \.self) { id in row(id) } }
                }
            }
            .environment(\.editMode, .constant(.active))
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

    @ViewBuilder private func row(_ id: String) -> some View {
        HStack {
            Text(InsightsCatalog.entry(id)?.title ?? id)
            Spacer()
            Toggle("", isOn: Binding(
                get: { layout.order.contains(id) },
                set: { isOn in
                    if isOn { if !layout.order.contains(id) { layout.order.append(id) } }
                    else { layout.order.removeAll { $0 == id } }
                    retag()
                })).labelsHidden()
        }
    }

    private func retag() { layout.templateName = layout.matchingTemplate()?.rawValue }
}
```

> Reuse `confirmCheckmarkStyle()` (Common/ViewModifiers). Toggling a hidden card on appends it to the end of `order`; off removes it. Reorder applies within the enabled section.

- [ ] **Step 2: Present it from the template menu**

Add `@State private var customizing = false`; add `Divider()` + `Button("Customize…") { customizing = true }` to the template `Menu`; and attach to the Trends content:
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

## Manual verification

**PR #1:** 1) fresh → Overview set, menu "Overview"; 2) menu → Spending/Wealth/Everything change the cards + label; 3) range still drives Monthly spending / Net worth / Cashflow; 4) Breakdown unchanged; 5) RecentExpenses + Holdings gone from Insights; macOS builds.
**PR #2:** 6) Customize → toggle off/on + drag reorder → menu flips to "Custom", persists across relaunch.

## Self-Review

- **Spec coverage:** registry + templates + layout + persistence + tests (T1, together to satisfy the `everything`→catalog dependency); render + menu (T2); Customize sheet + "Custom" (T3); drops the 2 duplicates (T1); Breakdown untouched; global `@AppStorage`; default overview. ✓
- **Type consistency:** `InsightsCatalog.all/.entry`, `InsightsCardEntry.make(_:)`, `InsightsTemplate.cardIDs/.title/.rawValue`, `InsightsLayout(order:templateName:)/.matchingTemplate()/.default` used identically across tasks. ✓
- **Ordering:** registry + model in one task (Task 1) resolves the `everything`/test → catalog compile dependency. ✓
