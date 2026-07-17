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

## Revision (user direction, same PR): thin accent stripe instead of icon-less rows

A 3pt leading **stripe** (rounded rect, row-height) replaces the removed icon's role — consistent
on every row, near-zero width, scannable down the column, and it carries **kind**, not just
direction: expense **red** · income **green** · **refund purple** (money back, deliberately
distinct from income — user call) · transfer **blue** · adjustment **gray**. The refund *badge*
also went green → purple to match. The amount **reverts to primary** (one signal, one place — no
red-heavy feed). Badges remain the accessible/semantic layer; the stripe is the at-a-glance one.

## Revision 2 (user direction): stripe replaces the badges too

With the stripe carrying kind, the **Refund / Transfer / Adjustment badges are removed** —
verified redundant: a transfer row's title *is* "Transfer" (entry description), adjustments say
"Balance adjustment", and refund reads from the purple stripe + positive amount. VoiceOver
retains the kind via an `accessibilityLabel` on the stripe (Expense/Income/Refund/Transfer/
Adjustment). Net row: `▎ merchant + pending/anomaly flags + chip · date/tags · amount` — no
new fallback strings introduced (badge texts gone; a11y labels reuse catalog terms).
