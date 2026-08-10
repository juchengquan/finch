# Reconcile becomes a MODE of the account screen — design

**Date:** 2026-08-10
**Status:** decided in a grilling session; supersedes the presentation half of
`2026-08-03-reconcile-redesign-design.md` while keeping its analysis. Read that
doc for the three defects of the shipped sheet, the currency argument, the
diagnosis rationale, and the commit guard — all carried forward.

## What changed since the Aug 3 doc, and why

| Axis | Aug 3 doc | Now | Why |
|---|---|---|---|
| Presentation | stays a SwiftUI sheet | **in-place MODE of account detail (iOS)** | reconciling IS working the account's list; a sheet re-renders that list one abstraction away |
| Default ticks | period starts ticked | **previously reconciled stay ticked; everything else enters UNTICKED** | owner's call: a tick is a deliberate act. Also dissolves the doc's open question #1 (first-ever ⇒ nothing prior ⇒ all unticked) and deletes the sticky-ticks recompute machinery |
| Completion | `Done` / `Adjust` toolbar | **no top-right button; "Finish reconciliation" MATERIALIZES in the header when the difference hits zero** | the zero-difference guard IS the gate; balanced-or-nothing |

## The mode

Entered from account detail (and every old sheet entry point routes here).
While active:

- **Header** (below the search bar): "Reconciling", current balance, statement
  balance (prefilled from current, editable), statement date (default today),
  the difference, the **show reconciled** toggle, and — only at difference zero
  — the Finish button.
- **List**: becomes multi-select in the app's ○/◉ idiom. Toggle OFF shows only
  unreconciled rows, grouped by the Aug 3 window: *In this period* /
  *After the statement* (cannot be on this statement) / *Still open from
  before*. Toggle ON reveals settled rows inline, ticked; unticking one stages
  an un-clear.
- **Chrome**: top-left ✕ Cancel exits discarding; top-right empty. The
  diagnosis (sign sentence + exact single-amount match + prefilled quick-add,
  provisional pending a look at the built UI) sits under the difference.
- **Ticks are staged** — zero writes while working. Finish fires ONE batched
  `setCleared` set (+ `confirmTransaction` for ticked pending rows) then
  `reconcileAccount`; a short batch refuses to seal (Aug 3 guard).
- **Native currency throughout** (`displayNative`), privacy-masked with a
  scoped reveal — both per the Aug 3 doc, unchanged.

## Platform scope

iOS only: the mode lives in `AccountDetailVC` (UIKit). `ReconcileSheet.swift`
survives strictly as the **macOS surface** (parked platform) and stops being
presented anywhere on iOS. macOS adopts the mode when macOS work resumes.

## Engine / parity

**Zero churn.** "Reconciled" is the existing `cleared_at`; the mode composes
`setCleared`, `confirmTransaction`, `addTransaction`, `reconcileAccount`;
`Selectors.reconcileState` computes the difference over staged-overlaid rows.
Nothing parity-gated changes, so `ReconcileModeTests` (window, staged
difference, diagnosis incl. the pair-false-positive rejection, commit guard)
carries the weight, plus a UI test: enter → tick → Finish seals; Cancel leaves
zero writes.
