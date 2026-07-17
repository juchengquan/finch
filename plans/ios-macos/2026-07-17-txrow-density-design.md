# TxRow: drop the leading kind icon (A1) + denser rows (b)

**Date:** 2026-07-17
**Status:** Approved, implemented inline.
**Scope:** The shared `TxRow` (feed, Account Detail, Counterparty Detail).

**A1 — consistent icon removal.** The leading kind icon was redundant for ~95% of rows
(expense/income direction = amount sign) and selectively keeping it looked inconsistent
(user feedback). Now: no leading icon on any row; the **amount carries the direction color**
(red/green — the icon's exact colors, relocated); **transfer/adjustment** get caption badges
in the title line, mirroring the existing Refund badge pattern. Refund keeps its badge.
`TxnKindIcon` remains in use elsewhere (Add sheet, detail).

**b — density.** `.listRowInsets(top/bottom 6, leading/trailing 20)` on the three TxRow row
sites (default ≈ 11pt vertical) + the row's two VStacks tightened `spacing: 2 → 1`.
Net: roughly 20–25% shorter rows, plus ~24pt reclaimed row width.

**Testing:** builds iOS + macOS; no scriptable route to a TxRow list (feed is behind a nav
push; `finch://` only handles `add`), so the visual is the human pass post-merge. New
fallback strings "Transfer"/"Adjustment" → next zh batch.
