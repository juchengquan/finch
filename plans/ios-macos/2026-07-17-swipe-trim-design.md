# Account rows: trim swipe actions (option A)

**Date:** 2026-07-17
**Status:** Approved, implemented inline. Follow-up to #466.
**Why:** Each swipe button has a ~75pt system-minimum width, so 3 trailing + 2 leading covered
~60% of the row on reveal. Styling can't shrink buttons (single-line rows already render
icon-only); the only real lever is fewer buttons per edge.

- **Trailing swipe:** Edit + Delete (was + Archive). Full swipe = Edit, unchanged.
- **Leading swipe:** Add Transaction only (was + Reconcile). Full swipe = Add, unchanged.
- **Context menu:** unchanged — the complete set (Add Transaction / Reconcile / Edit / Archive /
  Delete), so the demoted verbs stay one long-press (or right-click on macOS) away.

Principle: swipe = frequent verbs, menu = complete set (Mail/Reminders convention). Implemented
as swipe-specific builders (`trailingSwipeActions` / `leadingSwipeActions`) alongside the
complete `rowActions` / `leadingActions` used by the menu.

**Testing:** build iOS + macOS; sim launch sanity; gesture pass human-verified post-merge.
