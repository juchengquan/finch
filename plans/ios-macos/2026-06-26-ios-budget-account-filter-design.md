# Budgets per-account filter (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** FinchApp UI (`BudgetSheet` + `BudgetDetailView`) + one FinchCore guard test. **No engine/schema/projection/selector change.** Tier-2 parity.

## Problem

Web budgets can be scoped to specific **accounts** (multi-select) in addition to categories; iOS budgets expose only the **category** filter in the form. The matching gap is UI-only — the iOS engine already fully supports account-scoped budgets, it's just never surfaced.

## Key finding (verified)

The account filter is **already live end-to-end in the iOS engine** (like rollover/reconcile were):
- Schema: `budgets.account_ids TEXT` (JSON array). `BudgetRow.accountIds: [String]` projected via `parseIds`.
- Persistence: `createBudget`/`updateBudget` accept + persist `accountIds` (JSON), same path as `categoryIds`.
- **Matching** (`Selectors.budgetProgress`): `let accountSet = budget.accountIds.isEmpty ? nil : Set(...)` then `if let accountSet, !accountSet.contains(t.account) { continue }` — i.e. `(accountIds.isEmpty || tx.account ∈ accountIds) AND (categoryIds.isEmpty || tx.category ∈ categoryIds)`, both empty-means-all, AND-combined. Identical to the web.

So this feature only adds the form picker + a detail display, and a guard test for the existing matching.

## Non-goals

- No engine/schema/projection/`budgetProgress` change (all present + correct).
- No category-scope display change (out of scope; this is the account filter).

## Detailed design

### FinchApp — `BudgetSheet` (form)

Mirror the existing **category** multi-select for accounts:
- Add `@State private var selectedAccounts: Set<String>`, prefilled in `init` from `Set(budget?.accountIds ?? [])` (same as `selectedCategories`).
- Account source: `store.accounts` (active accounts of the ledger). Display `acct.name ?? "Account"`.
- A new `Section` after the categories section: a toggle row per account (`Button` → toggle membership; trailing `checkmark` when selected), header "Accounts", footer "Leave empty to track all accounts." (Cloned from the categories section.)
- Persist in `save()`: add `"accountIds": .array(selectedAccounts.sorted().map { .string($0) })` to the patch (update) **and** to the create args — exactly mirroring `categoryIds`.

### FinchApp — `BudgetDetailView`

Add an account-scope line in `progress(_:_:)` (the progress VStack), shown **only when `budget.accountIds` is non-empty** (the common all-accounts case stays uncluttered):
- `Text("Accounts: \(names)")` `.font(.caption).foregroundStyle(.secondary)`, where `names = budget.accountIds.compactMap { id in store.accounts.first { $0.id == id }?.name }.joined(separator: ", ")` (fall back to nothing if all unresolved).

### FinchCore — guard test

The account-matching predicate has no dedicated test. Add one (characterization — the engine already passes):
- Seed `l1` + accounts `a1`, `a2`; an expense budget with `accountIds: ["a1"]`, empty `categoryIds` (all categories); a same-cycle expense on `a1` and one on `a2`.
- Assert `budgetProgress.used` counts only the `a1` expense.
- A second budget with empty `accountIds` counts **both**.

## Facts (verified)

- `BudgetSheet.swift`: `selectedCategories: Set<String>` (prefilled from `budget?.categoryIds`); `categories` computed from `store.pickableCategories`; a toggle-row `Section` with empty-means-all footer; `save()` persists `categoryIds: .array(...)` in the patch + create. No account UI.
- `store.accounts: [AccountRow]` (active, projected) — the account source. `AccountRow.name: String?`.
- `BudgetDetailView.progress(_:_:)` is a VStack in the first `List` Section (used/base, carry-forward, bar, remaining, date range). No account scope shown today.
- `Selectors.budgetProgress` account+category matching as quoted above (no change needed).
- 0 open PRs touch `Budget*` (collision-checked); rollover (#311) already merged. `BudgetSheet`/`BudgetDetailView` are cold.

## Testing

- **FinchCore:** the account-matching guard test above (accountIds-scoped vs empty=all).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests + FinchCore green.
- **Manual (sim):** create/edit a budget → toggle one or more accounts → save; re-open Edit → the selection persists; BudgetDetail shows "Accounts: …" when filtered; spend on a non-selected account does **not** count toward the budget.

## Out of scope

Engine/schema/projection/`budgetProgress` changes; category-scope display; budget add-form frequency additions (separate Tier-3 item).
