# Spec: Activity detail column on iPad/macOS (#414 deferral, CP1)

**Date:** 2026-07-16
**Status:** design approved, ready for implementation plan
**Scope:** native app (`ios/`), regular-width shell only. First of the two remaining #414 deferrals (CP2 — the Scheduled detail column — is a separate spec). Compact/iPhone behavior is unchanged.

## Goal

Give the Activity feed the three-column treatment on iPad/macOS: sidebar │ feed │ **transaction detail**. Tapping a row selects it and fills the third column with a **read-only detail view + an Edit button** (the existing `EditTransactionSheet` stays the single write path — no extraction of its 374-line form; that "full inline editor" option was considered and rejected as L-sized/high-risk).

## Current state (baseline)

- `SplitViewShell` (AdaptiveShell.swift) gives `ThreeColumnShell` treatment to `.accounts`/`.budgets`/`.ledger` (each with a shell-held `String?` selection cleared on ledger switch); `.activity` falls into the 2-column `default:` branch.
- `ActivityFeedView` (Tabs/ActivityTab.swift): rows are `Button`s that open `EditTransactionSheet` via `@State editing: Tx?`; the `List` already binds `selection: $kbSel` (macOS ↵-open keyboard selection); receipts preview via `store.attachments(for:)` → `store.attachmentURL(for:)` → `.quickLookPreview($previewURL)`.
- Selection-mode convention (from #414/#23): `var selection: Binding<String?>? = nil` — non-nil ⇒ rows `.tag(id)` and select; nil ⇒ compact push/sheet behavior. Used by `AccountsTab`, `BudgetsTab`, `LedgerListView`.
- A `tx:` deep link (Spotlight/notification) sets `router.selectedTab = .activity` + `router.focusedId`; **compact** consumes it (TabBarShell's `focusedTx` sheet); **regular width drops it** today (nothing in `SplitViewShell` reads `focusedId`).
- `AccountDetailView` is the precedent for an inline detail surface with Edit-in-toolbar.

## Design

### 1. `TransactionDetailView(txId: String)` — new inline detail view

- New file `ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionDetailView.swift`.
- Resolves the transaction **live** from the store (`store.txns.first { $0.id == txId }`) so it reflects edits immediately; if the id no longer resolves, render `DetailPlaceholder(systemImage: "list.bullet", label: "Select a transaction")` (the shell also guards — see §3).
- Content (a `List`/`Form` of sections, all money via the store's privacy-aware formatters):
  - **Header:** merchant, prominent signed amount (`store.displayMoney(amount, from: currency)`), colored kind icon (`TxnKindIcon` + feed's sign/kind color convention).
  - **Facts:** date (+ time when present), category name (`store.categoryName`), account name, tags, note.
  - **Status:** pending vs confirmed (+ cleared-at when set).
  - **Splits:** when `splits` is non-empty, one row per split (category name + `displayMoneyBase(amountBase)`).
  - **Refund link:** when `refundedTransactionId` is set, a "Refunds ⟨merchant/date⟩" line (resolved from the store; plain text — no cross-navigation in CP1).
  - **Receipts:** when `store.attachments(for: txId)` is non-empty, a receipts row per attachment; tap → Quick Look (same `previewURL`/`.quickLookPreview` pattern as the feed/account detail).
- **Toolbar:** a single **Edit** button (`pencil` or text) presenting `EditTransactionSheet(txn:)` as a sheet. No delete/other actions in CP1 (they remain on the feed's swipe/context menus and in the sheet).

### 2. `ActivityFeedView` selection mode

- Add `var selection: Binding<String?>? = nil` (the established convention).
- When `selection` is non-nil:
  - The `List` binds to the **provided** binding (not `kbSel`) — one source of truth; rows render with `.tag(t.id)` and tapping selects instead of opening the edit sheet.
  - The macOS ↵-open behavior keys off the same provided binding in this mode (↵ may simply be redundant since selection already drives the detail column — implementer may keep ↵ as a no-op or map it to Edit; note the choice).
  - Multi-select/bulk mode (`isSelecting`) and swipe/context menus keep working unchanged.
- When nil: existing behavior byte-for-byte (compact + all current call sites — `ActivityTab`, Accounts' "All Transactions" push, `LedgerDetailView`).

### 3. Shell wiring (`SplitViewShell`)

- New `@State private var txSelection: String?`, cleared on ledger switch alongside `accountSelection`/`budgetSelection`.
- New `case .activity:` branch:
  ```
  ThreeColumnShell {
      ActivityFeedView(consumesPendingFilter: true, selection: $txSelection)
  } detail: {
      if let id = txSelection, store.txns.contains(where: { $0.id == id }) {
          NavigationStack { TransactionDetailView(txId: id) }
      } else {
          DetailPlaceholder(systemImage: "list.bullet", label: "Select a transaction")
      }
  }
  ```
  (Exact wrapper/params per the existing `.accounts` branch idiom; the feed keeps NOT owning a NavigationStack.)
- **Deep-link integration:** when `router.selectedTab == .activity && router.focusedId != nil` on regular width, consume it into `txSelection` (then clear `focusedId`) — a `tx:` Spotlight/notification tap now selects the transaction in the column instead of being dropped. This also gives verification a scripted path to drive selection.

## Non-goals

- No Scheduled detail column (CP2, own spec).
- No inline editing — Edit opens the existing sheet.
- No compact/iPhone changes; no changes to `EditTransactionSheet` itself.
- No cross-navigation from the refund-link line (plain text in CP1).

## Testing / verification

- **Builds:** `FinchApp` (iOS) + `FinchMac` (macOS); full `FinchAppTests` regression (feed behavior with `selection == nil` must be unchanged).
- **iPad simulator (scripted where possible):** launch on an iPad sim → Activity via the sidebar → screenshot shows feed + placeholder third column. If the deep-link path is drivable in the harness (e.g. via a debug `-initialTab activity` + programmatic focusedId is NOT externally settable — acknowledge honestly), selection verification falls back to a **manual checklist**: tap a row → detail fills; Edit → sheet → save → detail reflects the change; delete the selected tx from the feed → placeholder returns; compact iPhone feed still opens sheets on tap.
- **macOS:** build + a launch sanity check (selection is native on Mac lists).

## Risks

- `ActivityFeedView` is the app's hottest shared view (3 call sites + bulk mode + filters) — the `selection == nil` path must be provably unchanged; the reviewer should specifically compare the nil-path row rendering before/after.
- `kbSel` vs provided-binding unification: subtle — keep `kbSel` for nil-mode only, never both active.
- The `.activity` route on regular width (`syncFromRouter` equivalents) — verify tab switching to Activity via sidebar/⌘-number still works and the new branch doesn't disturb `MasterDetailShell`'s sidebar sections.
