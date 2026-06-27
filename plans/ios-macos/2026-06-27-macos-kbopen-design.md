# macOS keyboard-open on the Scheduled & Activity lists

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** On macOS, let keyboard users **arrow to a row and press ↵ to open its edit sheet** in the two primary sheet-based lists (Scheduled list-mode, Activity feed). UI only, no engine change.
**Context:** Follow-up to macOS parity Phase 3 (the Accounts/Budgets master-detail lists already open-on-select; these sheet-based lists had no selection model).

## Why these two only

Accounts/Budgets already open-on-arrow (their `List(selection:)` drives the detail pane).
The Scheduled and Activity lists open an **edit sheet** on click and have **no selection
model**, so a keyboard-only macOS user can't open a row. Power Tools lists are excluded
(lower traffic).

## Design — `List(selection:)` + `.onKeyPress(.return)`

Each list gains a keyboard-selection state and a macOS-only Return handler. Single click
still opens (the existing row `Button`), so this purely adds **arrow-select → ↵-open**.

### Scheduled (`ScheduledTab.swift`, list mode)
- Add `@State private var kbSel: String?`.
- `List {` → `List(selection: $kbSel) {`.
- Tag the template row: `Button { editing = t } …` gets a trailing `.tag(t.id)`.
- After the List's `.overlay { … }`, add:
  ```swift
  #if os(macOS)
  .onKeyPress(.return) {
      if let id = kbSel, let t = filteredScheduled.first(where: { $0.id == id }) { editing = t; return .handled }
      return .ignored
  }
  #endif
  ```
- Detected (not-scheduled) rows aren't tagged → ↵ no-ops on them (they're tap-to-add); fine.

### Activity (`ActivityTab.swift`, the feed)
- Add `@State private var kbSel: String?` (near `isSelecting`/`selected`).
- `List {` → `List(selection: $kbSel) {`.
- In `row(_ txn:)`, add `.tag(txn.id)` as the final modifier (covers both the grouped and
  flat `ForEach` paths, which both call `row`).
- After the List's closing `}` (before the `else`-branch close), add:
  ```swift
  #if os(macOS)
  .onKeyPress(.return) {
      if !isSelecting, let id = kbSel, let txn = sections.flatMap({ $0.txns }).first(where: { $0.id == id }) { editing = txn; return .handled }
      return .ignored
  }
  #endif
  ```
  (No-op while in bulk-select; the bulk `selected: Set` is independent of this single
  keyboard selection.)

## Cross-platform safety
- `List(selection:)` with a `String?` binding is **inert on iOS outside EditMode**; the
  app's bulk-select uses its own `isSelecting` flag (not SwiftUI EditMode), so iOS behaviour
  is unchanged. `.onKeyPress` is `#if os(macOS)`. `onKeyPress`/`KeyPress.return` are macOS 14+
  (the target floor). No engine change.

## Out of scope
- Power Tools lists; double-click (single click already opens); ↵ on detected/recurring rows;
  ↑/↓ customisation (List provides it).

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) — both `** BUILD SUCCEEDED **`.
- **macOS (best-effort):** run FinchMac, focus the Scheduled list / Activity feed, arrow to a
  row, press ↵ → its edit sheet opens. *Honest caveat:* ↵-on-a-focused-list isn't reliably
  scriptable under macOS automation, so the live keypress is verified by build + code review +
  the standard `onKeyPress` contract rather than an automated capture.
- **iOS:** unchanged (selection binding inert; `onKeyPress` compiled out).

## Notes
- Collision: `ScheduledTab`/`ActivityTab` are actively edited — re-check `gh pr list` + rebase
  before pushing; keep diffs to the listed spots. PR → `feat/frontend`.
