# Scheduled: calendar always visible (empty state only without accounts)

**Date:** 2026-07-19
**Status:** Approved in discussion; single-task inline plan below (combined doc).
**Scope:** `ScheduledTab.swift` + one zh-Hans catalog entry. No engine/web change.

## Problem

`ScheduledTab.swift:51` replaces the entire page with `EmptyState` when
`store.scheduled.isEmpty && detected.isEmpty`, so the calendar (default mode) never
renders on an empty ledger. The calendar should always show — its day-tap add
affordance (`onAdd` date prefill) makes an empty month grid more useful than the
dead-end empty state.

## Decisions

1. Full-page `EmptyState` remains ONLY for `store.accounts.isEmpty` (nothing can be
   scheduled; the + toolbar button is disabled) with the existing "Import a .finch
   pack or add an account first." description.
2. Otherwise the normal UI (mode picker + calendar/list) always renders. Calendar:
   empty month grid, day-tap add works. List mode when empty and not searching: a
   secondary-text hint row "Tap + or a calendar day to add a recurring transaction."
   (searching-empty keeps the existing `ContentUnavailableView.search` overlay).
3. New string gets zh-Hans in the same PR: 点按 + 或日历中的日期以添加定期交易。

## Plan (single task, inline)

- [ ] Change the guard at ScheduledTab.swift:51 from
  `store.scheduled.isEmpty && detected.isEmpty` to `store.accounts.isEmpty`; collapse
  the description ternary to the accounts-empty string.
- [ ] In list mode, after `modePickerRow`, insert the hint row when
  `filteredScheduled.isEmpty && filteredDetected.isEmpty && !searchActive`.
- [ ] Add the new key + zh-Hans to `Localizable.xcstrings`.
- [ ] Builds (FinchApp + FinchMac) + FinchAppTests; sim: with data, page unchanged;
  empty-ledger case is a human pass (calendar grid + day-tap add).
- [ ] Commit `fix(ios): Scheduled — always show the calendar; empty state only without accounts`; PR.
