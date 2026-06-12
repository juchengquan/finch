# finch for iOS & macOS — Phase 2 Implementation Design

> **Status**: design spec — not yet an implementation plan. Once approved,
> this becomes the input to `writing-plans` to produce a step-by-step
> implementation plan for Phase 2.
>
> Companion documents:
>
> - `plans/IOS_MACOS_PLAN.md` — the direction brief
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` — full design for Phase 1.0
> - `plans/IOS_MACOS_PHASE_1_5_DESIGN.md` — full design for Phase 1.5
> - `plans/IOS_MACOS_ROADMAP.md` — the 8-phase arc (Phase 2 is sketched
>   there; this is the **full design** for that sketch)
> - `plans/IOS_MACOS_PHASE_2_DESIGN.md` (this file)
>
> _Audience: the engineers who will build the iOS app. Assumes Phase 1.0
> and Phase 1.5 are complete; the `Project` + `Money` + `Audit` + `Pack` +
> `Selectors` modules exist, the read-only UI is shipped, the
> JSON-golden parity harness is in place._

## §1. Goal & non-goals

**Goal** — Add the **74-action write chokepoint** to FinchCore (port of
`lib/db/core/entries.ts` + 13 per-domain `lib/db/domain/<x>/mutations.ts`
files) + ship the **7 new iOS write screens** (Add Transaction, Edit
Transaction, Transaction Detail edits, Pending confirm, Budget CRUD,
Scheduled CRUD, Ledger CRUD, plus the full Holdings tab + CRUD UI
per Q32) + ship the **write-side round-trip parity
suite** (74 fixtures, one per action). The app becomes "usable for real"
— every action the web supports, the iOS app supports, with the same
final state.

**Phase 2 is the largest single piece of the iOS/macOS project.** It
unlocks every later phase that drives writes (Phase 4 power features,
Phase 5 auto-pack debounce, Phase 6 App Intents, Phase 7 widgets). The
per-domain dispatch + write chokepoint port is the architecture that
every later phase builds on.

**Non-goals (firm)**:

- **iPad / macOS adaptive layout** — Phase 3. The 7 new screens render
  the same on iPhone as the 5 read-only tabs in Phase 1.5 do (a single
  `NavigationStack` per screen).
- **Power features** (reconcile UI, rules engine + builder + backfill,
  transfers CRUD, merchants / categories / tags admin, saved searches,
  bulk recategorize, FX / base tools) — Phase 4. The **actions** for
  these land in Phase 2 (the dispatch handles them); the **UI** for
  them is Phase 4. The user can call them via the Swift-side chokepoint
  but no iOS screen surfaces them in Phase 2.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **App Intents / Siri / Share Extension receipts / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Widgets / Watch / Live Activities** — Phase 7.
- **Row-level sync** — Phase 8.
- **Anomaly threshold tuning UI** — the `anomalyScore` thresholds from
  the web are used as-is in Phase 1.0. A UI for tuning them is Phase 4.
- **Offline write queue** — every write in Phase 2 goes through the
  chokepoint synchronously. There's no "edit offline, sync later"
  queue. That requires a non-trivial design (conflict resolution on
  reconnect) and lands in Phase 5 alongside the auto-pack debounce.
- **Multi-user / shared ledgers** — single-user iCloud account = single
  finch install. Per the plan's §10 resolved decision.
- **Android** — not in the plan.

**Estimated scope**: ~2,400 lines TS to port (823-line chokepoint + 1,335
lines per-domain + ~250 lines of glue) + ~1,750 lines SwiftUI
(7 new screens, including the full Holdings CRUD UI per Q32) +
~3,700 lines parity fixtures (74 fixtures × ~50 lines
each) + ~200 lines UI plumbing. **3-4 months of full-time work** for a
small team. **Largest in Swift port scope (larger than Phase 1.0 and
Phase 1.5 combined).**

**Pre-Phase-2 prerequisite**: a web-side cleanup PR that deletes the
3 dead-code duplicates in `accounts/mutations.ts`
(`createAccountGroup` / `updateAccountGroup` / `deleteAccountGroup`).
This PR lands BEFORE the Phase 2 iOS port starts. The iOS port
lands against the cleaned-up web. Estimated size: ~30 lines
removed from `accounts/mutations.ts` + parity tests confirming
the 3 actions still resolve correctly to the canonical
`accountGroups/mutations.ts` versions. Landed in ~1 day.

## §2. What gets ported (the surface area)

The web's write surface is **3 layers**:

1. **The chokepoint** — `lib/db/core/entries.ts` (823 lines) — the
   12-export module that owns entries/postings writes. Phase 1.0
   ported the **read-only half** (`auditLedger` +
   `recomputeAccountFromPostings`). Phase 2 ports the **write half**
   (`postEntry`, `postSimple`, `postTransfer`, `postAdjustment`,
   `postOpening`, `rebuildEntry`, `deleteEntry`, plus `ensureSystemCategories`,
   `resolveEntryRef`, `dedupHash`, `isAccountLeg`).
2. **The 13 per-domain `mutations.ts` files** — 1,335 lines total —
   each exporting a `handlers` map keyed by action name. The handlers
   compose the chokepoint with cross-domain glue
   (`withDedupMessage`, `txTouches`, `invalidateRollover`,
   `unlinkAttachmentFiles`, etc.).
3. **The dispatcher** — `lib/db/mutate.ts` (53 lines) — merges the 14
   per-domain `handlers` maps into one `ALL` map and routes
   `applyMutation(exec, action, args)` to the right handler.
4. **The `_args.ts` registry** — `lib/db/domain/_args.ts` (225 lines) —
   the central per-action `Args` type + the derived `ActionName` type
   (74 actions, all typed). This is the **wire contract** that ties
   everything together.

Plus the **server-side glue**:

- `lib/db/core/server.ts::withWrite` — the write-lock primitive
  (BEGIN/COMMIT, SAVEPOINT, post-write `auditLedger` cache
  invalidation)
- `lib/db/core/server.ts::getCachedAudit` — Phase 1.0 ported the
  read-only version; Phase 2 wires it to the write cache invalidation
  (every successful write clears the cache for the affected ledger)
- `lib/db/core/server.ts::autoBackup` — the periodic `.finch.bak`
  writer (Phase 2 ports the trigger logic; Phase 5 ties it to the
  debounce)

The **route layer** (`/api/mutate`) is the web's bridge from HTTP to
`applyMutation`. The iOS app has no HTTP route — it calls
`FinchStore.apply(action, args)` directly on the in-process DB. The
`_args.ts` registry's `ActionName` type + the dispatcher are the iOS
side's wire contract, identical to the web's.

### Per-domain surface (74 actions)

| Domain | `mutations.ts` size | Actions | Notable cross-domain deps |
|---|---|---|---|
| `transactions` | 370 lines | 15 (`addTransaction`, `updateTransaction`, `deleteTransaction`, `setCleared`, `setReviewed`, `markAllReviewed`, `reconcileAccount`, `adjustAccountBalance`, `bulkRecategorize`, `removeAttachment`, `confirmTransaction`, `confirmPendingWithMerchant`, `confirmAllPending`, `setTransactionSplits`, `setTransactionTags`) | `attachments` (cleanup), `budgets/rollover` (invalidate) |
| `scheduled` | 192 lines | 8 (`createScheduled`, `updateScheduled`, `deleteScheduled`, `addScheduledSplit`, `removeScheduledSplit`, `postScheduled`, `updateScheduledSplit`, `generateDueScheduled`) | `counterparties` (resolve) |
| `rules` | 161 lines | 4 (`createRule`, `updateRule`, `deleteRule`, `backfillRule`) | `counterparties` (resolve) |
| `budgets` | 106 lines | 10 (`createBudget`, `updateBudget`, `deleteBudget`, `contributeBudget`, `clearPendingAmount`, `createBudgetGroup`, `updateBudgetGroup`, `deleteBudgetGroup`, `updateBudgetCycle`, `removeBudget`) | `budgetGroups` (read; `createBudgetGroup` / `updateBudgetGroup` / `deleteBudgetGroup` also have a duplicate implementation in `accountGroups/`, see note below) |
| `holdings` | 84 lines | 4 (`createHolding`, `updateHolding`, `deleteHolding`, `setHoldingPrice`) | — |
| `ledgers` | 82 lines | 5 (`createLedger`, `updateLedger`, `changeLedgerBase`, `setDefaultLedger`, `deleteLedger`) | — |
| `accounts` | 73 lines | 5 accounts-only (`createAccount`, `updateAccount`, `archiveAccount`, `unarchiveAccount`, `deleteAccount`) | `accountGroups` (read; `createAccountGroup` / `updateAccountGroup` / `deleteAccountGroup` are duplicated in this file — see note below) |
| `transfers` | 57 lines | 3 (`createTransfer`, `updateTransfer`, `deleteTransfer`) | `transactions` (read), `accounts` (read) |
| `tags` | 38 lines | 3 (`createTag`, `updateTag`, `deleteTag`) | `transactions` (read; tag application is via `setTransactionTags`, not a separate `addTagToTransaction` action) |
| `counterparties` | 41 lines | 5 (`createCounterparty`, `updateCounterparty`, `deleteCounterparty`, `verifyCounterparty`, `unverifyCounterparty`) | — |
| `categories` | 48 lines | 3 (`createCategory`, `updateCategory`, `deleteCategory`) | — |
| `accountGroups` | 35 lines | 3 (`createAccountGroup`, `updateAccountGroup`, `deleteAccountGroup`) | — (these are also duplicated in `accounts/`, see note below) |
| `app` (cross-cutting) | 48 lines | 7 (`setMobileTabIds`, `setBackupFrequency`, `setBackupRetention`, `setDisplayCurrency`, `setExchangeRate`, `deleteExchangeRate`, `reset`) | — |
| **Total** | **1,335 lines** | **77 entries / 74 unique actions** | 5 known cross-domain deps |

**Note on the `accountGroups` / `accounts` duplication**: the web's
`accounts/mutations.ts` (73 lines) exports a `handlers` map that
includes `createAccountGroup`, `updateAccountGroup`, and
`deleteAccountGroup` — the same 3 actions exported by the canonical
`accountGroups/mutations.ts` (35 lines). The dispatcher
(`lib/db/mutate.ts`) imports **both** `accountsHandlers` and
`accountGroupsHandlers` and merges them into one `ALL` map. Because
`accountsHandlers` is spread first (line 28 in `mutate.ts`), the
`accounts` versions win for the 3 overlapping actions, making the
`accountGroups/` handlers effectively dead code.

**The web gets the cleanup as a separate PR before Phase 2** (per
the resolution-pass decision). The cleanup deletes the 3 dead
duplicates from `accounts/mutations.ts`; the canonical
`accountGroups/mutations.ts` versions are the live ones. The Phase
2 iOS port lands against the cleaned-up web. The Swift dispatcher
imports the per-domain `handlers` maps 1:1 with the web (the
dispatcher order in `mutate.ts` is preserved on the Swift side;
the 3 actions resolve to the `accountGroups/` handlers, not the
`accounts/` handlers).

If for any reason the web-side cleanup PR has not landed by the
time the Phase 2 iOS port starts, the port mirrors the bug 1:1
(the `accounts/` versions win in the Swift dispatcher) and a
follow-up cleanup PR fixes both sides. The cleaner outcome is the
upstream fix; the fallback is acceptable.

Per the plan's §2.1 and the AGENTS.md layer rules, the **5 known
cross-domain deps** are:

- `accounts → accountGroups`
- `transactions → attachments`
- `budgets → budgetGroups`
- `rules → counterparties`
- `scheduled → counterparties`

These were called out in the AGENTS.md as "5 known cross-domain deps
currently use direct `queries` imports." The Swift port mirrors the
same direct-import pattern (not via `_deps.ts` shims — those aren't
created yet on the web side; we don't create them in Phase 2 either).

## §3. `Store` module layer rules

Per the Phase 1.0 spec's §3, the `Store` module is the **9th
FinchCore module** (added in Phase 2; the 8 from Phases 1.0 + 1.5
stay unchanged).

**Layer rules** (the only allowed import directions; enforced by
`FinchCoreArchitectureTests`):

- `Store` imports `DB`, `Money`, `Schema`
- `Store` does NOT import `Project`, `Selectors`, or `Audit` directly
  (the chokepoint and per-domain handlers operate on raw DB rows via
  `Exec`; the post-write re-projection is the dispatcher's job — see
  §9.1)
- `Store` does NOT import `Pack` (writes go through the in-process DB,
  not the pack engine; the pack engine only runs on the user's
  explicit Export tap and the Phase 5 auto-pack debounce)
- `Store` does NOT import `ICloud` (the iCloud folder-watcher is
  Phase 5)
- `Selectors` (from Phase 1.5) does NOT import `Store` (selectors are
  read-only; the write chokepoint reads from selectors' results but
  not vice versa — `Store` can call `Selectors` at the dispatcher
  boundary, not the other way around)

```
┌──────────┐
│  Money   │  (unchanged; Decimal end-to-end)
└────┬─────┘
     │
┌────▼─────┐
│  Store   │  (NEW in Phase 2; imports DB/Money/Schema)
└────┬─────┘
     │
┌────▼─────┐
│  DB      │  (unchanged; Exec / Row types)
└──────────┘
     ↑
     (post-write re-projection is done at the dispatcher's boundary;
      Store doesn't depend on Project / Selectors / Audit directly)
```

`Store` is the **only module that writes**. It contains:

- `Store/Entries/` — the chokepoint port (12 exports from
  `lib/db/core/entries.ts`)
- `Store/Domain/<x>/` — the 13 per-domain `mutations.ts` ports
  (each exporting a `handlers` map)
- `Store/Apply.swift` — the dispatcher (53 lines, mirrors
  `lib/db/mutate.ts`)
- `Store/Args.swift` — the `_args.ts` port (the central
  `ActionName` enum + `Args` type registry)
- `Store/Shared/` — cross-domain helpers (the 5 known
  cross-domain deps + `withDedupMessage`, `txTouches`,
  `invalidateRollover`, `unlinkAttachmentFiles`, etc.)
- `Store/WithWrite.swift` — the write-lock primitive (mirrors
  `lib/db/core/server.ts::withWrite`)

The Swift `Store` module is the **only** module that ever mutates
the DB. Every UI action that writes (the 7 new screens in Phase 2,
the App Intents in Phase 6, the widgets in Phase 7) routes through
`FinchStore.apply(action, args)` → `Apply.applyMutation` → the
per-domain handler → the chokepoint.

**Defense in depth**: the chokepoint + the schema triggers + the
audit gate are layered (per the plan's §4.6). A handler that
forgets to forward `cleared_at` on a `rebuildEntry` patch is
caught by the audit gate on the next import. The Swift port
honors the same defense in depth: the chokepoint enforces the
preconditions, the triggers enforce the invariants, the audit gate
verifies both.

## §4. The chokepoint port

`lib/db/core/entries.ts` is **823 lines** with 12 exports. Phase 1.0
ported the **read-only half** (`auditLedger` (already done) +
`recomputeAccountFromPostings` (already done)). Phase 2 ports the
**write half**:

### 4.1 — Exports to port

| Export | Signature | Notes |
|---|---|---|
| `ensureSystemCategories` | `(exec: Exec, ledgerId: string) -> Promise<SystemCategoryIds>` | Already in Phase 1.0 (called by the seed + import). Re-listed for completeness. |
| `isAccountLeg` | `(l: LegInput) -> l is AccountLegInput` | Type guard, trivial. |
| `dedupHash` | `(date, time, description, legs) -> String?` | Pure compute; no IO. |
| `postEntry` | `(exec: Exec, e: NewEntry) -> Promise<{ entryId: string }>` | The primary write. |
| `postSimple` | `(exec: Exec, s: SimpleEntryInput) -> Promise<{ entryId: string }>` | Sugar for single-category entries. |
| `postTransfer` | `(exec: Exec, a: TransferInput) -> Promise<{ entryId: string }>` | Sugar for two-account transfers. |
| `postAdjustment` | `(exec: Exec, a: AdjustmentInput) -> Promise<{ entryId: string }>` | Sugar for balance adjustments. |
| `postOpening` | `(exec: Exec, o: OpeningInput) -> Promise<{ entryId: string }>` | Sugar for opening balances. |
| `recomputeAccountFromPostings` | `(exec: Exec, accountId: string) -> Promise<void>` | Already in Phase 1.0 (audit helper). Re-listed. |
| `rebuildEntry` | `(exec: Exec, entryId: string, patch: EntryPatch) -> Promise<{ touchedAccountIds: string[] }>` | The patch primitive. |
| `deleteEntry` | `(exec: Exec, entryId: string) -> Promise<{ touchedAccountIds: string[] }>` | The delete primitive. |
| `resolveEntryRef` | `(exec: Exec, id: string) -> Promise<EntryRef?>` | Resolve a stored entry id to its kind/ledger/date. |
| `auditLedger` | `(exec: Exec, ledgerId?, opts?) -> Promise<AuditProblem[]>` | Already in Phase 1.0. Re-listed. |

**`postEntry` is the most important function in the entire
codebase.** It's the single write path that every mutation funnels
through (the 5 sugar functions are thin wrappers). The port
preserves every invariant the web enforces:

- The legs balance to 0 in the ledger base (rounded to 2 dp; the
  `r2` helper from `lib/db/core/entries.ts` line 24)
- The `currency` on each account leg is the account's currency
  (the schema's I3 invariant; the audit gate catches violations)
- The `amountBase` is derived from `amount + exchangeRate` unless
  pinned (the I9 invariant; the chokepoint honors pinned rates
  verbatim)
- The `clearedAt` is forwarded (the §2.6 adapter precondition; the
  chokepoint does NOT default to `NULL` if the original was set)
- The `categoryId` on `kind='expense'` legs is non-null (the I5
  invariant)
- The `id`, if provided, is preserved (the DE migration's
  id-reuse policy; Phase 1.0's pre-DE `.finch` round-trip relies
  on this)
- The schema triggers handle the rest (seal/posting/balance
  triggers; Phase 1.0 already created them)

**`rebuildEntry` has 2 known adapter preconditions** (called out
in the plan's §2.6 and the Phase 1.0 spec's §2.6 footnote):

1. **Forward `cleared_at`**: when patching, the caller MUST forward
   the original `cleared_at` value. Omission silently un-clears a
   reconciled row. The Swift port enforces this via the `EntryPatch`
   struct's `clearedAt` field being explicit (no default to `nil`
   in the patch).
2. **Pass explicit `amountBase` for pinned rates**: when the
   entry carries user-pinned rates (a date edit must preserve
   them), the caller MUST pass explicit `amountBase` values. The
   default re-locks from the rates table, which can change the
   converted amount. The Swift port enforces this via the
   `AccountLegInput.amountBase` field being optional but the
   `rebuildEntry` codepath raising an `I18nError` if it's missing
   for a pinned-rate leg.

### 4.2 — `withWrite` write-lock primitive

`lib/db/core/server.ts::withWrite` (port from Phase 2) is the
write-lock primitive. It:

1. Acquires an exclusive write lock on the DB (GRDB's
   `DatabaseQueue.write { ... }` block)
2. Begins a transaction
3. Runs the caller's `fn(exec)` inside the transaction
4. On commit, invalidates the `getCachedAudit` cache for the
   affected ledger
5. On error, rolls back; the live DB is untouched

The Swift port uses GRDB's `DatabaseQueue` (the Phase 1.0
choice — single-writer, no concurrent writes):

```swift
// Store/WithWrite.swift
public func withWrite<T>(
  _ db: GRDB.DatabaseQueue,
  _ fn: (any Exec) async throws -> T
) async throws -> T {
  try await db.write { grdb in
    let exec = GRDBExec(grdb)
    let result = try await fn(exec)
    // Phase 2: invalidate audit cache for affected ledgers
    // (the function returns a `touchedLedgerIds` set; we read it
    //  from the Exec context).
    await AuditCache.invalidate(ledgerIds: exec.touchedLedgerIds)
    return result
  }
}
```

`GRDBExec` is a thin wrapper around `GRDB.Database` that conforms
to the `Exec` protocol — the same pattern the web's `lib/db/core/repo.ts`
defines. Phase 1.0's `DB` module ports the read-side `Exec`; Phase
2 extends it with the write-side audit-cache invalidation.

### 4.3 — `getCachedAudit` invalidation

Phase 1.0 ported the **read-side** `getCachedAudit` (the cached
read of `auditLedger` keyed on the ledger id + last-modified
timestamp). Phase 2 wires the **write-side invalidation**: every
successful `withWrite` call invalidates the cache for any ledger
the write touched (per the `touchedLedgerIds` set on the `Exec`
context). This is the same pattern the web uses (per the
`_resetAuditCacheForTests` test hook + the
`_setAuditClockForTests` clock injection from PR #138).

## §5. The `_args.ts` registry

`lib/db/domain/_args.ts` (225 lines) is the central per-action
`Args` type + the derived `ActionName = keyof Args` type. The
Swift port mirrors this with a Swift `enum` + an associated-value
`Args` enum case per action:

```swift
// Store/Args.swift
public enum ActionName: String, CaseIterable, Sendable {
    case addTransaction
    case updateTransaction
    // ... 74 cases total
}

public enum Args: Sendable {
    case addTransaction(AddTransactionArgs)
    case updateTransaction(UpdateTransactionArgs)
    // ... 74 cases total

    var actionName: ActionName { /* map back */ }
    static func from(action: ActionName, raw: [String: Any]) throws -> Args { /* decode */ }
}
```

The 74 `Args` shapes are ported 1:1 from the web. Each
`AddTransactionArgs`, `UpdateTransactionArgs`, etc. is a Swift
struct with the same fields as the web's TypeScript shape (e.g.,
`AddInput` from `lib/db/domain/transactions/types.ts`).

**This is the wire contract.** Every consumer (the dispatcher,
the per-domain handlers, the parity tests, the future App Intents
in Phase 6) reads from this one file. Drift surfaces as a Swift
compile error at the dispatcher.

The dispatcher's `applyMutation` becomes:

```swift
// Store/Apply.swift
public enum Store {
    public static func applyMutation(
        _ db: GRDB.DatabaseQueue,
        action: String,
        args: [String: Any]
    ) async throws {
        let parsed = try Args.from(action: /* parse action name */, raw: args)
        let handler = ALL[parsed.actionName]
        guard let handler else {
            throw I18nError(code: "error.unknownAction", params: ["action": action])
        }
        try await withWrite(db) { exec in
            try await handler(exec, parsed)
        }
    }

    // ALL is the merged handlers map, computed at static init time
    // from each per-domain handlers map.
}
```

## §6. Per-domain `mutations.ts` ports

The 13 per-domain `mutations.ts` files (1,335 lines total) port
mechanically. The pattern is identical in every file:

```swift
// Store/Domain/<x>/Mutations.swift
public let handlers: [ActionName: Handler] = [
    .addTransaction: { exec, args in /* ... */ },
    .updateTransaction: { exec, args in /* ... */ },
    // ...
]

typealias Handler = (any Exec, Args) async throws -> Void
```

Each handler:

1. Decodes its `Args` subtype from the `Args` enum case
2. Calls the chokepoint (or one of its sugar wrappers) via `Exec`
3. Handles cross-domain glue: `withDedupMessage`, `txTouches`,
   `invalidateRollover`, `unlinkAttachmentFiles`, etc.
4. Returns nothing (writes are fire-and-forget; the dispatcher
   returns the post-write projected state to the caller)

The 5 known cross-domain deps are direct `queries` imports (not
via `_deps.ts` shims — those aren't created on the web side; we
don't create them in Phase 2 either, per the AGENTS.md "5 known
cross-domain deps currently use direct `queries` imports" note).

**Example: `transactions/mutations.ts` port** (370 lines TS →
~370 lines Swift; the patterns are 1:1)

```swift
// Store/Domain/transactions/Mutations.swift
public let handlers: [ActionName: Handler] = [
    .addTransaction: { exec, args in
        guard case .addTransaction(let a) = args else { fatalError("type mismatch") }
        let id = try await withDedupMessage {
            try await qAddTransaction(exec, a)
        }
        if let touches = try await txTouches(exec, id) {
            try await invalidateRollover(
                exec,
                .init(categoryIds: touches.categoryIds, accountIds: [touches.accountId]),
                touches.date
            )
        }
    },
    .updateTransaction: { exec, args in
        // ... ported 1:1 from the web
    },
    // ... 12 actions total for transactions/
]
```

### Cross-domain shared helpers

The shared helpers (`withDedupMessage`, `txTouches`,
`invalidateRollover`, `unlinkAttachmentFiles`, etc.) live in
`Store/Shared/`. They're ported from
`lib/db/domain/_shared/*.ts` (and the per-domain glue in
`lib/db/domain/_app/`).

`withDedupMessage` is the most important: it wraps a write in a
"deduplicate transaction" check (the `dedupHash` from the
chokepoint) and re-throws with a friendly "this looks like a
duplicate" `I18nError` if a match is found. The web uses this in
~8 places (every action that creates a new transaction). The
Swift port has the same pattern.

## §7. The 7 new iOS screens

Phase 2 ships 7 new iOS screens (the **write surfaces**). Each
screen is a SwiftUI form sheet that calls into the chokepoint via
`FinchStore.apply(action, args)`. The screens are read-write
companions to the read-only tabs from Phases 1.0 + 1.5.

### 7.1 — Add Transaction

The "you tapped the + button in the bottom bar" screen. Full
form for adding a new transaction (expense, income, transfer,
adjustment, refund). ~500 lines SwiftUI.

```
┌─────────────────────────────────────┐
│  ← Add Transaction         [Save]   │
├─────────────────────────────────────┤
│  [Expense] [Income] [Transfer]      │
│                                      │
│  Amount                              │
│  ┌──────────┐  USD ▾               │
│  │  87.23   │                       │
│  └──────────┘                       │
│                                      │
│  Account                             │
│  Chase Checking                  ▾   │
│                                      │
│  Date                                │
│  Jun 12, 2026                    ▾   │
│                                      │
│  Description                         │
│  ┌──────────────────────────────┐   │
│  │ Whole Foods                  │   │
│  └──────────────────────────────┘   │
│                                      │
│  Category                            │
│  🛒 Groceries                    ▾   │
│                                      │
│  Tags                            [+] │
│  ── personal                        │
│                                      │
│  Notes                               │
│  ┌──────────────────────────────┐   │
│  │                              │   │
│  └──────────────────────────────┘   │
│                                      │
│  ── More ──                         │
│  Status:        ( ) Pending          │
│                (•) Confirmed         │
│  Time:          14:30                 │
│  Cleared:       ( ) Mark cleared     │
│  Counterparty:  ▾                     │
│                                      │
│  [Cancel]                            │
└─────────────────────────────────────┘
```

**Args** (the wire shape): `Args.addTransaction(AddInput)` from
`lib/db/domain/transactions/types.ts` — the same shape the web's
"Add Transaction" dialog sends. The Swift port passes the form
fields to `FinchStore.apply(.addTransaction, .init(...))`; the
chokepoint posts the entry; the Activity tab refreshes.

**Validation**: amount > 0, account selected, date valid, category
required for `kind='expense'`, description non-empty. On submit,
the form calls `FinchStore.apply` and shows a loading overlay
("Posting…"). On success, the form dismisses and the Activity tab
shows the new row. On error, a typed `StoreError` alert.

### 7.2 — Edit Transaction

The "tap a row in the Activity tab and edit it" screen. Same
form as Add, pre-filled with the existing values. ~450 lines
SwiftUI.

**Args**: `Args.updateTransaction(UpdateTransactionArgs)` — the
patch shape from the web. The form diffs the original `Tx` and
the form state, builds the patch, calls
`FinchStore.apply(.updateTransaction, .init(id, patch))`.

**Critical preconditions** (from §4.1):

- The form preserves the original `clearedAt` (if the user
  didn't change the "Mark cleared" toggle, the patch keeps the
  original value)
- The form preserves the original `amountBase` for pinned-rate
  legs (the chokepoint re-locks from the rates table on date
  edit unless `amountBase` is in the patch)

### 7.3 — Transaction Detail edits

The "tap a row in the Activity tab to see the full detail" screen.
Phase 1.0's Transaction Detail is **read-only**; Phase 2 adds
edit affordances: a "Edit" button in the toolbar that pushes the
Edit Transaction form, plus inline "Mark cleared" / "Mark
reviewed" / "Delete" actions.

**Actions surfaced**:

- **Mark cleared** → `Args.setCleared({id, cleared: true})`
- **Mark reviewed** → `Args.setReviewed({id, reviewed: true})`
- **Delete** → `Args.deleteTransaction({id})` (with a confirm
  dialog: "Delete this transaction? This cannot be undone.")
- **Confirm pending** → `Args.confirmTransaction({id})` (only
  shown for `pending=true` rows)

### 7.4 — Pending confirm flow

A specialized view in the Activity tab for `pending=true` rows.
"Pending" means the transaction was created by a recurring
template or a scheduled item and hasn't been confirmed yet. The
web has a "Pending" tab (Phase 1.0 read-only; Phase 2 read-write).

**Actions surfaced**:

- **Confirm** → `Args.confirmTransaction({id})` (single tap;
  the chokepoint posts it; the activity list refreshes)
- **Confirm with merchant** → `Args.confirmPendingWithMerchant({id, counterpartyId})`
  (a sub-sheet: pick an existing counterparty or create a new one;
  the chokepoint resolves the merchant name and stamps the
  `counterpartyId` on the entry)
- **Edit before confirming** → pushes the Edit Transaction form

### 7.5 — Budget CRUD

The "tap a budget to edit it; tap + in the Budgets tab to add
one" screen. ~400 lines SwiftUI.

**Args**:

- **Create** → `Args.createBudget(NewBudgetInput)` (with a
  `NewBudgetGroup` if the user picks a new group)
- **Update** → `Args.updateBudget({id, patch: BudgetPatch})`
- **Delete** → `Args.deleteBudget({id})` (with a confirm dialog)
- **Contribute** → `Args.contributeBudget({budgetId, amount, date})`
  (a sub-flow: "add $200 to your Groceries budget for June")
- **Group CRUD** → `Args.addBudgetGroup`, `Args.updateBudgetGroup`,
  `Args.deleteBudgetGroup`

### 7.6 — Scheduled CRUD

The "tap a scheduled template to edit it; tap + in the Scheduled
tab to add one" screen. ~400 lines SwiftUI. Note: the **Scheduled
tab** itself is read-only in Phase 1.0; Phase 2 adds the read-write
**Scheduled** tab (with the existing 5-tab navigation — from
Phase 1.5's Insights add — getting a 6th write-able Scheduled
tab — but the read surface mirrors what Phase
1.0's `scheduled` selector would have shown, had we included it in
Phase 1.5). ~600 lines SwiftUI total for the tab + form.

**Args**:

- **Create** → `Args.createScheduled(NewScheduledInput)`
- **Update** → `Args.updateScheduled({id, patch: ScheduledPatch})`
- **Delete** → `Args.deleteScheduled({id})` (with a confirm
  dialog: "Delete this scheduled template? Future occurrences
  will not be generated.")
- **Post now** → `Args.postScheduled({id})` (a button: "Post
  the next occurrence now"; the chokepoint generates the entry
  and stamps the `sourceTemplateId` on it)
- **Add/remove split** → `Args.addScheduledSplit`,
  `Args.removeScheduledSplit` (for split-income templates)
- **Generate due** → `Args.generateDueScheduled({asOf: date})` (a
  top-level button: "Generate all due scheduled items"; the
  chokepoint materializes the past-due occurrences)

### 7.7 — Ledger CRUD

The "tap a ledger in the Settings tab to edit it; tap + in the
ledger switcher to add one" screen. ~300 lines SwiftUI.

**Args**:

- **Create** → `Args.createLedger(NewLedgerInput)` (the user
  picks a name, base currency, color, and whether it's the
  default)
- **Update** → `Args.updateLedger({id, patch: LedgerPatch})`
- **Change base** → `Args.changeLedgerBase({id, newBase})` (a
  destructive action: changing the base currency re-rates every
  historic entry at the new base; the form shows a confirm
  dialog with the count of affected entries)
- **Set default** → `Args.setDefaultLedger({id})` (a single tap)
- **Delete** → `Args.deleteLedger({id})` (a destructive action;
   the chokepoint cascades to every account/entry/category in the
   ledger; the form shows a confirm dialog with the count of
   affected rows)

### 7.8 — Holdings tab + full CRUD UI

Per Q32, Phase 2 ships a full Holdings tab (the 7th of the 6
new write screens). The tab is reachable from the Accounts
tab (Accounts › [account name] › Holdings section) or as a
top-level tab per the implementation-time UX decision.

**Args** (the wire shape): the 4 holdings actions from the
chokepoint:
- `createHolding({accountId, symbol, quantity, costBasis})`
- `updateHolding({id, patch: HoldingPatch})`
- `deleteHolding({id})`
- `setHoldingPrice({holdingId, date, price})`

**Layout sketch** (the Holdings list view, embedded in the
Account Detail screen):

```
┌─────────────────────────────────────┐
│  ← Chase Checking                    │
├─────────────────────────────────────┤
│  Holdings (4)                       │
│  ─────────────────                  │
│  AAPL                                │
│     10 shares @ $178.50              │
│     Last price: $182.30 (Jun 12)     │
│     Gain: ▲ $38.00 (+2.1%)           │
│     [Edit price] [Edit] [Delete]     │
│                                      │
│  VTI                                │
│     25 shares @ $220.00              │
│     Last price: $235.10 (Jun 12)     │
│     Gain: ▲ $377.50 (+6.9%)          │
│     [Edit price] [Edit] [Delete]     │
│                                      │
│  [+ Add holding]                     │
└─────────────────────────────────────┘
```

The **Add holding** form:
```
┌─────────────────────────────────────┐
│  ← Add Holding                       │
├─────────────────────────────────────┤
│  Account (default: current account) │
│  Chase Checking                  ▾   │
│                                      │
│  Symbol                              │
│  ┌──────────────────────────────┐   │
│  │ AAPL                          │   │
│  └──────────────────────────────┘   │
│                                      │
│  Quantity                            │
│  ┌──────────┐                        │
│  │  10      │                        │
│  └──────────┘                        │
│                                      │
│  Cost basis                          │
│  ┌──────────┐  USD ▾               │
│  │  178.50  │                       │
│  └──────────┘                       │
│                                      │
│  Initial price (optional)            │
│  ┌──────────┐  USD ▾               │
│  │  178.50  │                       │
│  └──────────┘                       │
│                                      │
│  [Cancel]                  [Save]    │
└─────────────────────────────────────┘
```

The **Edit holding** form is similar (the symbol is read-only;
the quantity + cost basis are editable; the price is editable
via a separate "Edit price" action).

The **Edit price** action is a single-field form:
```
┌─────────────────────────────────────┐
│  ← Edit Price · AAPL                 │
├─────────────────────────────────────┤
│  Price                               │
│  ┌──────────┐  USD ▾               │
│  │  182.30  │                       │
│  └──────────┘                       │
│                                      │
│  Date (default: today)               │
│  Jun 12, 2026                    ▾   │
│                                      │
│  [Cancel]                  [Save]    │
└─────────────────────────────────────┘
```

The **Delete holding** action shows a confirm dialog:
"Delete this holding? The price history is preserved;
the holding won't appear in the portfolio summary."
On confirm, `Args.deleteHolding({id})` is dispatched.

**Holdings + 1.5 + 2 selectors**: the Holdings tab reads from
Phase 1.5's `holdingsForAccount`, `holdingValue`,
`holdingGainLoss`, `holdingsValueForAccount` selectors (the
Phase 1.5 spec's "Holdings" group of 4 selectors). The 4
selectors are in-memory; the CRUD UI writes through the
chokepoint and triggers a re-projection on the Phase 1.5
selectors.

### 7.9 — Shared UX patterns

All 7 screens share these patterns:

- **Form sheet** (modal in the SwiftUI `NavigationStack`; dismisses
  on Cancel or after a successful Save)
- **Loading state**: full-form `ProgressView` overlay with a
  status string ("Posting…" / "Updating…" / "Deleting…")
- **Error state**: typed `StoreError` alert (the same `I18nError`
  type the web's API throws; the iOS side maps it to a localized
  message via `Localizable.strings`)
- **Empty / not-found state**: the form shows "This transaction
  was deleted" or "This ledger no longer exists" and offers a
  "Back" button
- **Accessibility**: every field has a VoiceOver label; the
  amount input announces the currency; the date picker announces
  the full date
- **Theming**: matches Phase 1.0 + 1.5's light/dark tokens; the
  form fields use the same `Money` + `Date` primitives

## §8. Write-side round-trip parity

Phase 2's parity suite is the **most complex** of the three
parity suites (1.0, 1.5, 2). For each of the 74 actions, the
parity test:

1. Loads a known pre-state `.db` fixture (a small `transactions.finch`
   with seeded accounts / categories / counterparties / etc.)
2. Calls `applyMutation(exec, action, args)` on both Swift and
   TS
3. Compares the **post-state `.db`** (byte-for-byte via
   `VACUUM INTO` and sha256) AND the **post-write projected
   `Tx[]`** (struct-by-struct)
4. Asserts the audit gate (`auditLedger`) reports clean on both
   post-states

The 74 fixtures live at
`ios/FinchCore/Tests/Fixtures/actions/<action-name>.finch` (the
pre-state) + a JSON file
`ios/FinchCore/Tests/Fixtures/actions/<action-name>.json` (the
expected post-state `Tx[]` + the expected `auditLedger`
result).

### 8.1 — Fixture format

Each action fixture is a **pair**:

- `actions/addTransaction.finch` — the pre-state DB (a seeded
  sample with 3 accounts, 5 categories, 2 counterparties, 0
  entries; the test loads this, calls `addTransaction` with
  args `{accountId, amount, date, description, categoryId}`, and
  asserts the post-state matches the expected)
- `actions/addTransaction.json` — the expected post-state
  ```json
  {
    "action": "addTransaction",
    "args": {
      "accountId": "acc-checking",
      "amount": 87.23,
      "date": "2026-06-12",
      "description": "Whole Foods",
      "categoryId": "cat-groceries"
    },
    "expectedTxns": [
      {
        "id": "<uuid>",
        "merchant": "Whole Foods",
        "category": "Groceries",
        "amount": 87.23,
        "account": "Chase Checking",
        "date": "2026-06-12",
        "kind": "expense"
      }
    ],
    "expectedAudit": [],
    "expectedDbSha256": "<hex>"
  }
  ```

### 8.2 — The fixture export script

The Phase 1.0 + 1.5 `frontend/scripts/export-fixtures.ts` extends
to also write the 74 action fixtures. For each action:

1. Generate a pre-state `.finch` by running the seed
   (`lib/db/core/seed.ts::seedSampleLedger`) with a known
   variant (the variant is `actions/<action-name>`; each action
   gets a variant tuned to its args — `addTransaction` uses
   `variant=addTransaction`, `updateLedger` uses
   `variant=updateLedger`, etc.)
2. Run the action via the web's `applyMutation(exec, action,
   args)` with a known args payload
3. Capture the post-state `.db` (via `VACUUM INTO`)
4. Capture the post-write projected `Tx[]` (via
   `lib/db/state.ts::projectState`)
5. Capture the post-write `auditLedger` result
6. Write the `.finch` (pre-state) and `.json` (expected
   post-state) to `ios/FinchCore/Tests/Fixtures/actions/`

The script handles 74 actions × ~5 KB per fixture ≈ ~370 KB
total. CI runs the script before `FinchCore` tests; the Swift
parity tests read the fixtures and assert.

### 8.3 — Swift `ParityTests` extension

Phase 1.5's `ParityTests` target adds a 5th test type: **per-
action write-side round-trip parity**. The test runner
discovers all `.finch` + `.json` pairs in
`ios/FinchCore/Tests/Fixtures/actions/` and generates one Swift
test per pair:

```swift
// ios/FinchCore/Tests/ParityTests/ActionParityTests.swift
final class ActionParityTests: XCTestCase {
    func test_AllActions() throws {
        let fixturesDir = Bundle.module.url(forResource: "Fixtures/actions", withExtension: nil)!
        let actions = try discoverActions(in: fixturesDir)

        for action in actions {
            try runActionParityTest(action)
        }
    }

    private func runActionParityTest(_ action: ActionFixture) throws {
        // 1. Open the pre-state .db in Swift
        let store = try openSwiftStore(finch: action.finchURL)
        // 2. Apply the action
        try await Store.applyMutation(store.db, action: action.action, args: action.args)
        // 3. Capture the post-state .db sha256
        let actualDbSha = try store.db.vacuumInto().sha256
        XCTAssertEqual(actualDbSha, action.expectedDbSha256, "db sha mismatch for \(action.action)")
        // 4. Capture the post-state Tx[] and compare
        let actualTxns = try Project.run(on: store.db)
        XCTAssertEqual(actualTxns, action.expectedTxns, "tx[] mismatch for \(action.action)")
        // 5. Run auditLedger and compare
        let actualAudit = try Audit.run(on: store.db, ledgerId: store.activeLedgerId)
        XCTAssertEqual(actualAudit, action.expectedAudit, "audit mismatch for \(action.action)")
    }
}
```

### 8.4 — Test target structure

After Phase 2, the 3 SwiftPM test targets are:

- `FinchCoreTests` — unit tests for each module (the 9
  modules: `Money`, `DB`, `Schema`, `Project`, `Audit`, `Pack`,
  `Selectors`, **`Store`**, `ICloud`)
- `ParityTests` — 5 test types: `Tx` projection parity,
  `auditLedger` parity, `.db` round-trip parity (Phase 1.0);
  per-selector JSON-golden parity (Phase 1.5);
  **per-action write-side round-trip parity** (Phase 2)
- `FinchAppTests` — UI snapshot tests for the **7 new screens**
  + the 5 read-only tabs (Accounts, Activity, Budgets, Insights,
  Settings)

No structural change to the CI workflow; the macos job from
`IOS_MACOS_PHASE_1_DESIGN §9` runs unchanged. The fixture
export script's action-export step is added to the `Export
fixtures` CI step.

## §9. Cross-cutting changes to existing code

Phase 2 touches a few files from Phases 1.0 + 1.5:

### 9.1 — `FinchStore.apply` (new in Phase 2)

Phase 1.0's `FinchStore` is a singleton holding the live DB +
the projected `Tx[]` cache. Phase 2 adds `apply`:

```swift
// iOS FinchStore (extends the Phase 1.0 class)
@MainActor
@Observable
public final class FinchStore {
    public func apply(action: String, args: [String: Any]) async throws {
        // 1. Persist the write via the chokepoint
        try await Store.applyMutation(db, action: action, args: args)
        // 2. Re-run the projection (Phase 1.0's `Project.run`)
        let newTxns = try await Project.run(on: db, ledgerId: activeLedgerId)
        // 3. Update the in-memory cache
        self.txns = newTxns
        // 4. Re-run the selectors that derived state depends on
        //    (e.g., net worth, account balances)
        self.derivedState = try await Selectors.recomputeAll(txns: newTxns, accounts: self.accounts, ...)
    }
}
```

The UI binds to the `txns` and `derivedState` `@Observable`
properties; after a write, the views re-render with the new
data.

### 9.2 — `Selectors` extension

Phase 1.5's `Selectors` module gains a `recomputeAll` helper
that runs every selector and caches the result. This is a
small wrapper that calls the 25 selectors in sequence (the
Insights tab's "every card re-evaluates against the new
end-month" behavior) and returns a `DerivedState` struct.

### 9.3 — UI for the 7 new screens

Each of the 7 new screens is a new SwiftUI view in
`ios/FinchApp/FinchApp/`. The screens are reachable from:

- **Add Transaction**: the + button in the bottom tab bar (a
  new "+" action; Phase 1.0 had a placeholder; Phase 2 wires
  it to Add Transaction)
- **Edit Transaction**: the Edit button in the Transaction
  Detail toolbar
- **Transaction Detail edits**: the inline actions in
  Transaction Detail
- **Pending confirm flow**: the "Pending" tab in the bottom
  bar (Phase 1.0 had a placeholder; Phase 2 wires it to the
  pending list)
- **Budget CRUD**: the + button in the Budgets tab + the tap
  on a budget row
- **Scheduled CRUD**: the + button in the Scheduled tab + the
  tap on a scheduled row
- **Ledger CRUD**: the + button in the ledger switcher + the
  tap on a ledger row in Settings

### 9.4 — I18n on iOS

The web's `I18nError(code, params)` shape is the wire contract.
The iOS side maps each `code` to a `Localizable.strings` entry.
Phase 2's first cut ships `en` (English) + the codes from the
web's `lib/i18n-error.ts` (~30 codes total). `zh-CN` lands
later as a product call.

## §10. Open questions

The plan's §14.1 still-open questions mostly land in later phases.
For Phase 2 specifically:

**Not blocking Phase 2 (decide later)**:

- **Day-1 locales**: the iOS app uses `Localizable.strings`;
  the day-1 list is a product call (default `en`; `zh-CN`
  optional).
- **Offline write queue**: every write in Phase 2 is
  synchronous (no "edit offline, sync later"). The pack-based
  sync model in Phase 5 effectively handles this: the user
  edits on iPhone → the change is in the local DB → the next
  pack (auto or manual) syncs it to the web. The intermediate
  "edit, app goes to background, app reopens" case is handled
  by GRDB's WAL + the `apply` function's
  transactional-atomicity guarantee. No "outbox" pattern
  needed in Phase 2.
- **Anomaly threshold tuning UI**: the existing
  `anomalyScore` thresholds from the web are used as-is.
  Tuning UI is Phase 4.
- **iCloud folder naming polish**: the user-visible "finch/"
  subfolder name in iCloud Drive is auto-created; polish
  (icon, custom folder name) is a follow-up.

**Specifically for the chokepoint port**:

- **Pinned-rate edit semantics**: the web's `rebuildEntry`
  honors pinned rates verbatim when `amountBase` is in the
  patch. The Swift port matches. If the user edits a
  transaction with a pinned rate, the form should surface
  "Rate pinned" as a warning and offer an "Unpin and
  re-lock from rates table" option. Phase 2 ships the
  warning; the "Unpin" action is Phase 4 (FX / base tools).
- **The "Force import" UI** (from Phase 1.0's Settings
  › Advanced — always visible, not behind a debug flag)
  is preserved for parity-test fixtures that intentionally
  violate the audit gate. The "Force write" equivalent
  doesn't exist — there's no scenario where a write should
  bypass the chokepoint's invariants (that's the whole
  point of the chokepoint).
- **Sealed-entry id stability**: the chokepoint's id-reuse
  policy (preserve the original entry id when patching) is
  required for cross-app pack round-trip. The Swift port
  honors this; the parity test asserts the policy
  (specifically: the `addTransaction` parity test uses a
  known id; the post-state `Tx[]` includes that id
  verbatim).

**Specifically for the per-action parity**:

- **Fixture count**: 74 actions × 1-3 fixtures per action =
  ~150-220 total fixtures. The Phase 1.0 + 1.5 harness
  scales to this; each test is millisecond-scale. ~1-2
  minutes total runtime.
- **Cross-action dependencies**: some actions depend on the
  side effects of other actions (e.g., `bulkRecategorize`
  requires entries to exist; `addTransaction` requires an
  account to exist). The fixture export script handles this
  by giving each action its own pre-state seed (e.g., the
  `bulkRecategorize.finch` has 5 pre-existing entries; the
  `addTransaction.finch` has 0 pre-existing entries). The
  Swift test runner doesn't need to chain actions.

**Not blocking Phase 2 because they're Phase 3+ by design**:

- **iPad / macOS adaptive layout** — Phase 3. The 6 new
  screens render the same on iPhone as in Phase 1.5 (single
  `NavigationStack` per screen).
- **Power features UI** (reconcile UI, rules engine +
  builder, transfers CRUD, etc.) — Phase 4. The actions
  land in Phase 2; the UI for them is Phase 4.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **App Intents / Siri / Share Extension receipts** —
  Phase 6. App Intents dispatch through `FinchStore.apply`,
  so the chokepoint is reusable.
- **Widgets / Watch / Live Activities** — Phase 7.

## §11. Out of scope (firm)

These are explicitly NOT in Phase 2:

- **iPad / macOS adaptive layout** — Phase 3.
- **Power features UI** (reconcile UI, rules engine + builder,
  transfers CRUD, merchants / categories / tags admin, saved
  searches, bulk recategorize, FX / base tools) — Phase 4.
  The **actions** for these land in Phase 2; the **UI** for
  them is Phase 4. The user can call them via the
  Swift-side chokepoint but no iOS screen surfaces them in
  Phase 2.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **App Intents / Siri / Share Extension receipts /
  Spotlight / notifications / biometric lock** — Phase 6.
- **Widgets / Watch / Live Activities** — Phase 7.
- **Row-level sync** — Phase 8.
- **In-app theme override** — Phase 2 follows the system
  light/dark setting.
- **Anomaly threshold tuning UI** — Phase 4.
- **Holdings tab + full CRUD UI** — Phase 2 ships a full
  Holdings tab (Accounts tab › Holdings section, or a
  dedicated tab per the UX; UI mockup at implementation
  time). CRUD surfaces: add holding (symbol, quantity,
  cost basis, account), edit holding, delete holding, add
  price update. The chokepoint's 4 holdings actions
  (`createHolding`, `updateHolding`, `deleteHolding`,
  `setHoldingPrice`) are the full surface. **The Holdings
  tab is the 7th of the 7 new write screens** (the spec
  now calls it "7 new write screens"; Holdings is the 7th;
  the spec's line count has been updated to reflect 7).
- **Rate editor** — Phase 4 ("FX / base tools").
- **Offline write queue** — every write is synchronous. The
  pack-based sync model in Phase 5 effectively handles
  offline edits via the "edit on iPhone, next pack syncs"
  pattern.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision.
- **Android** — not in the plan.

## §12. Spec self-review

(Inline review at write time; not part of the published spec.)

- **Placeholders**: none. Every section has concrete content.
  The 74-action surface is enumerated explicitly in §2's
  per-domain table.
- **Internal consistency**: §3's `Store` layer rules match the
  Phase 1.0 + 1.5 spec's §3 layer diagram (the 8 existing
  modules are unchanged; `Store` is the 9th, imports
  `DB`/`Money`/`Schema`; no `Project`/`Selectors`/`Audit`
  deps — the post-write re-projection is the dispatcher's
  job, not the chokepoint's). §4's chokepoint exports match
  the web's `lib/db/core/entries.ts` line-by-line. §6's per-
  domain handlers match the web's per-domain
  `mutations.ts` files (the 5 known cross-domain deps are
  direct `queries` imports per the AGENTS.md note). §8's
  parity harness extends the Phase 1.5 harness.

  Per-domain action counts cross-checked against the web:
  the live dispatcher merges 77 handler entries (74 unique
  action names; 3 are duplicates in `accounts/mutations.ts`
  for `createAccountGroup` / `updateAccountGroup` /
  `deleteAccountGroup` — these are dead in `accountGroups/`
  but live in `accounts/`. The web gets the cleanup as a
  separate PR before Phase 2; the iOS port lands against
  the cleaned-up web. If the web cleanup hasn't landed by
  the time the Phase 2 port starts, the port mirrors the
  bug 1:1 as a fallback).
- **Scope**: focused on Phase 2. Phase 1.0 + 1.5 are
  referenced as completed. Phase 3+ are explicitly out of
  scope (§11). The 7 new screens are specced at the same
  depth as Phase 1.0's tab specs.
- **Ambiguity**: §2's per-domain table enumerates all 14
  domains with their line counts + action counts + cross-
  domain deps. §4.1's chokepoint exports are listed with
  signatures + notes. §4.1's `rebuildEntry` preconditions
  (forward `cleared_at`; pass explicit `amountBase` for
  pinned rates) are called out explicitly with the
  enforcement mechanism. §5's `ActionName` enum + `Args`
  enum shape is shown with a concrete code example. §6's
  cross-domain shared helpers are named. §7's 7 new screens
  each have a wire shape (the `Args` enum case), a layout
  sketch, and the actions surfaced. §8's parity fixture
  format is shown with a concrete example. The 5 cross-
  cutting changes in §9 are each enumerated with their
  Phase 1.0 + 1.5 counterparts.
