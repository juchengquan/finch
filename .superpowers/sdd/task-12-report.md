# Tasks 1 & 2 Report — tx duplicate

**Status:** DONE
**Commit:** 4962af6 `feat(ios): leading-swipe Duplicate on transaction rows (feed, account & counterparty detail)` (4 files, +51, no Co-Authored-By)
**Builds:** iOS (FinchApp, iPhone 17 Pro sim) `** BUILD SUCCEEDED **`; macOS (FinchMac) `** BUILD SUCCEEDED **`

## What was done
- **Task 1** — `FinchStore+ViewHelpers.swift`: added `duplicateTransaction(_ txn: Tx) throws` exactly as in the plan, placed after `transactions(for:)`. `apply` was directly callable (same as `setDisplayCurrency`), so no fallback needed.
- **Task 2**
  - `Tabs/ActivityTab.swift` — `row(_ txn:)`: Duplicate leading-swipe button (indigo, `plus.square.on.square`) AFTER the pending-Confirm `if`; context-menu entry after Edit; `duplicate(_:)` uses the file's `run {}` wrapper.
  - `WriteScreens/AccountDetailView.swift` — `txRow(_ t:)`: same swipe + context-menu additions; `duplicateTxn(_:)` mirrors `confirmTxn` (`errorMessage = i18nMessage(error)`).
  - `PowerTools/CounterpartyDetailView.swift` — added `.swipeActions(edge: .leading)` + `.contextMenu` (Edit + Duplicate) to the `ForEach(txns)` row per the plan; added `@State private var errorMessage: String?` + `.errorAlert($errorMessage)` (file had no error state) and a `duplicate(_:)` matching the do/catch + `i18nMessage` pattern.

## Adaptations
- None material. Anchors matched the plan verbatim; only cosmetic addition was a blank line after the new helper in ViewHelpers.
- Trailing swipes, Confirm buttons, and the engine untouched. Eligibility guard `["expense", "income"].contains(kind ?? "")` identical at all three sites.
