# Budgets: manual reorder (Accounts-style drag), schema-free via app_state

**Date:** 2026-07-17
**Status:** Design approved, pending implementation
**Scope:** Long-press-drag budget rows within a group on the Budgets page (the Accounts
within-group convention), persisted per-ledger — **without** adding `budgets.sort_order`
(off-limits: shared pack schema). Order lives in the `app_state` KV, exactly like
`displayCurrencyByLedger` / `mobileTabs` (an ordered-ids precedent).

## Engine (FinchCore — small, additive, pack-safe)

1. **`ActionName`**: `case setBudgetOrder` (next to `setDisplayCurrency`).
2. **`Store/Domain/App.swift`**: handler entry + func mirroring `setDisplayCurrency`:
   ```swift
   static func setBudgetOrder(_ db: Database, _ args: Args) throws {
       struct A: Decodable { let ledgerId: String; let budgetIds: [String] }
       let a = try args.to(A.self)
       var map: [String: [String]] = [:]
       if let raw = try getAppState(db, "budgetOrderByLedger"), let data = raw.data(using: .utf8),
          let parsed = try? JSONDecoder().decode([String: [String]].self, from: data) { map = parsed }
       map[a.ledgerId] = a.budgetIds
       try setAppState(db, "budgetOrderByLedger", String(data: try JSONEncoder().encode(map), encoding: .utf8) ?? "{}")
   }
   ```
3. **`Projections+State.swift`**: `budgetOrderByLedger(dbQueue:) -> [String: [String]]`,
   mirroring the `displayCurrencyByLedger` reader.
4. **Unit test** (FinchCoreTests): apply `setBudgetOrder` → projection returns the map;
   second apply for another ledger merges (doesn't clobber).

Pack/web safety: `app_state` already travels in packs; unknown keys are ignored by the web
until it adopts `budgetOrderByLedger`. No schema, no migration, no parity-fixture change.

## Store plumb (`FinchStore.swift`)

`var budgetOrderByLedger: [String: [String]] = [:]` + read in the refresh path next to
`displayCurrencyByLedger` (same `Projection.` call site).

## Ordering application (`FinchStore+ViewHelpers.swift`)

```swift
    /// Apply the user's manual order (app_state budgetOrderByLedger); unknown ids
    /// (e.g. newly created budgets) keep their relative created_at order, after
    /// the ordered ones.
    private func applyBudgetOrder(_ list: [BudgetRow]) -> [BudgetRow] {
        guard let order = budgetOrderByLedger[activeLedgerId], !order.isEmpty else { return list }
        let pos = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return list.enumerated().sorted {
            (pos[$0.element.id] ?? order.count + $0.offset) < (pos[$1.element.id] ?? order.count + $1.offset)
        }.map(\.element)
    }
```
Wrap the returns of `budgets(in:)` and `ungroupedBudgets` with it.

## UI (`BudgetsTab.swift` — the Accounts convention)

- Grouped rows: `ForEach(filteredBudgets(in: groupName)) { … }` gains
  `.onMove { moveBudgets(in: groupName, from: $0, to: $1) }` (long-press drag, like
  `moveAccounts(in:)`). Ungrouped section's ForEach: same with group `"Ungrouped"`
  (`budgets(in:)` already maps nil→"Ungrouped").
- ```swift
  private func moveBudgets(in group: String, from source: IndexSet, to dest: Int) {
      guard !searchActive else { return }          // filtered indices would misalign
      var seg = store.budgets(in: group)
      seg.move(fromOffsets: source, toOffset: dest)
      var ids: [String] = []
      for g in store.budgetGroupsOrdered + ["Ungrouped"] {
          ids += (g == group ? seg : store.budgets(in: g)).map(\.id)
      }
      do { try store.apply(.setBudgetOrder, Args(["ledgerId": .string(store.activeLedgerId), "budgetIds": .array(ids.map { .string($0) })])) }
      catch { errorMessage = i18nMessage(error) }
  }
  ```
  (Persists the ledger-wide flat order — group membership itself is unaffected.)

## Out of scope
- `budgets.sort_order` column (schema); web UI adoption; cross-group drag (membership stays
  in Edit Budget); reordering while searching (guarded no-op).

## Testing
- **Unit:** the FinchCore test above.
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** DB-level proof — apply an order via the action path (or drag by hand),
  relaunch, page renders the saved order; new budgets append at the end.
