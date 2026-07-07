# iPad multi-column — Ledger 3-column + column-width polish — Implementation Plan

**Spec:** `plans/ios-macos/2026-07-07-ipad-multicolumn-design.md`. Three tasks; all view/shell wiring, no FinchCore changes, no new files.

## Task 1 — `LedgerListView` + `LedgerTab` dual mode

`ios/FinchApp/Sources/FinchApp/WriteScreens/LedgerManagementView.swift`:
- Add `var selection: Binding<String?>? = nil` to `LedgerListView` (the #23 convention: non-nil → three-column selection mode).
- Row builder: selection mode renders the row content directly with `.tag(ledger.id)` inside `List(selection: selection)`; compact mode keeps `NavigationLink(value:)` + the existing `.navigationDestination(for: String.self)`. Swipe actions, context menu, delete confirmation, `+` toolbar, sheets unchanged in both modes.

`ios/FinchApp/Sources/FinchApp/Tabs/LedgerTab.swift`:
- Add the same optional binding and forward it: `LedgerListView(selection: selection)`.

## Task 2 — `SplitViewShell` `.ledger` case

`ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift`:
- Add `@State private var ledgerSelection: String?`.
- Add a `case .ledger:` branch building `ThreeColumnShell { LedgerTab(selection: $ledgerSelection) } detail: { … }` with the stale-id guard (`store.ledgers.contains`) and `DetailPlaceholder(systemImage: "books.vertical", label: "Select a ledger")`; detail wraps `LedgerDetailView(ledgerId:)` in a `NavigationStack`.
- Do **not** add `ledgerSelection` to the active-ledger `onChange` reset (global list; see spec).
- Update the `SplitViewShell` doc comment (Accounts/Budgets → Accounts/Budgets/Ledger).

## Task 3 — column widths + doc sweep

`ios/FinchApp/Sources/FinchApp/Shell/MasterDetailShell.swift`:
- In `ThreeColumnShell`: `SectionSidebar().navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)`; `list().navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)`.
- Update the header comment (#23 note) to include Ledger.

Docs: handoff backlog "Polish themes" row — split out iPad multi-column as its own row: 🟡 Ledger 3-column + column widths shipped; Activity/Scheduled detail columns + visibility persistence deferred (this spec records why).

## Verification

- No FinchCore changes → ParityTests unaffected. No new unit-testable logic (pure SwiftUI wiring).
- CI proves: FinchApp (iOS) build + tests, FinchMac build (the `.ledger` branch and width modifiers are cross-platform APIs — no `#if os` needed; `navigationSplitViewColumnWidth` is available on macOS 13+/iOS 16+, targets are macOS 14/iOS 17).
- Simulator pass (post-merge, by hand per the handoff's sim caveat): iPad landscape Ledger 3-column flow; iPhone compact push unchanged.
