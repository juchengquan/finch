# Database layer architecture

> **Status:** post-refactor (2026-06). The `frontend/lib/db/` directory is layered: `core/` → `domain/` → `mutate.ts`.

This is the contributor-facing reference for the post-refactor layout. The agent-facing orientation lives in `frontend/AGENTS.md`; this document is the deeper dive.

## Layers

### `lib/db/core/` — the DB engine

Plain DB access. No business logic, no knowledge of any specific domain.

| File | Purpose |
|---|---|
| `driver.ts` | Cross-runtime SQLite driver (`better-sqlite3` server, `bun:sqlite` tests) |
| `schema.ts` | Canonical `SCHEMA`, `SCHEMA_VERSION`, `MIGRATIONS`, `migrate()`, `applySchema()` |
| `entries.ts` | Posting logic, `recomputeAccountFromPostings`, `auditLedger`, `rebuildEntry` |
| `entries-schema.ts` | The schema DDL for entries / postings / entry_attachments / entries_fts |
| `repo.ts` | `Exec`, `Row`, `SqlBind`, `PersistState`, `ProjectedState` |
| `seed.ts` | `seedReference`, `insertTransactions`, `seedTransactionTags` |
| `server.ts` | `getServerDb`, `withWrite`, `getCachedAudit`, `importDbBytes`, `exportDbBytes` |
| `paths.ts` | File path resolution for attachments |
| `sealed-entry.ts` | The two-phase sealed-insert helpers (`insertSealedEntry`, `appendResidueIfNeeded`) |
| `checksum.ts` | Checksum for pack import/export |
| `pack.ts` | Pack format (`.finch` files) |
| `storage.ts` | File storage abstraction |
| `test-utils.ts` | `bareDb`, `freshDb`, `seededDb`, `seededAndAudited` (the test harness) |

The `I18nError` class and the wire-format helpers (`fromWireError`, `toWireError`) live one level up at `lib/i18n-error.ts` — they're shared with the client (`lib/api-client.ts`) and the route handler (`app/api/mutate/route.ts`), so they sit outside the DB engine.

**Cannot import from `domain/*`.**

### `lib/db/domain/` — per-domain slices

One folder per first-class domain. Each folder is self-contained. There are 14 first-class domains: `accounts/`, `accountGroups/`, `transactions/`, `budgets/`, `budgetGroups/`, `categories/`, `counterparties/`, `tags/`, `rules/`, `scheduled/`, `transfers/`, `holdings/`, `attachments/`, `ledgers/`.

> **Note:** `accountGroups/` and `budgetGroups/` are first-class domains with their own `queries.ts` / `mutations.ts` / `types.ts` — they are *not* merged into `accounts/` or `budgets/`.

| Domain | What it owns |
|---|---|
| `accounts/` | Account rows + create/update/archive/unarchive/delete; I18nError codes |
| `accountGroups/` | Account-group rows + create/update/delete |
| `transactions/` | Transaction (entry + postings) rows, addTransaction / updateTransaction / deleteTransaction / setCleared / setReviewed / markAllReviewed / reconcileAccount / bulkRecategorize / confirmTransaction / confirmPendingWithMerchant / confirmAllPending / adjustAccountBalance / removeAttachment; I18nError codes |
| `budgets/` | Budget rows; I18nError codes |
| `budgetGroups/` | Budget-group rows |
| `categories/` | Category rows + 3-level depth helpers (in `_depth.ts`); I18nError codes |
| `counterparties/` | Counterparty rows + verify/unverify |
| `tags/` | Tag rows |
| `rules/` | Conditional rules + backfill |
| `scheduled/` | Scheduled templates + postScheduled + generateDueScheduled (helpers in `_helpers.ts`) |
| `transfers/` | Transfer rows; I18nError codes |
| `holdings/` | Holding rows + price updates |
| `attachments/` | Attachment rows + file resolution; I18nError codes |
| `ledgers/` | Ledger rows + recomputeAmountBases; I18nError codes |

The actual SQL (`q*` functions) lives in `lib/db/queries/<x>.ts` — a sibling of `core/`. Each per-domain `domain/<x>/queries.ts` is a thin re-export shim that adds the type re-exports:

```ts
// lib/db/domain/accounts/queries.ts
export * from '@/lib/db/queries/accounts';
export type { AccountRow, AccountPatch, NewAccount } from './types';
```

External consumers should import from `lib/db/domain/<x>/queries` (the shim), not from `lib/db/queries/<x>` (the engine-internal file). The shim is the public read-API surface.

**`errors.ts` is optional.** Domains that throw I18nErrors have one (e.g. `accounts`, `transactions`, `budgets`, `categories`, `transfers`, `attachments`, `ledgers`). Domains whose handlers only do SQL and never throw (`tags`, `counterparties`, `holdings`, `rules`, `accountGroups`, `budgetGroups`) omit it.

**`mutations.ts` is optional.** Domains that have wire actions have one. `budgetGroups/` is currently read-only on the wire and omits it.

Per-domain folder structure (when fully populated):

```
domain/<x>/
├── queries.ts        # re-exports from lib/db/queries/<x>.ts + type re-exports
├── queries.test.ts   # tests for queries (4 domains have these)
├── types.ts          # row + patch + input shapes (no SQL imports)
├── errors.ts         # I18nError code constants (as const) — optional
├── mutations.ts      # per-action handlers (a `handlers` map keyed by ActionName) — optional
└── mutations.test.ts # tests for the per-action handlers (7 domains have these)
```

Plus two escape hatches:

- `domain/_shared/` — cross-cutting helpers used by more than one domain. Currently: `with-dedup-message.ts`, `tx-touches.ts`, `ids.ts` (newId), `post-helpers.ts` (postSingle), `reset-tables.ts` (resetDb), `backup-config.ts` (mergeBackupConfig), `attachment-cleanup.ts` (unlinkAttachmentFiles), `mobile-tabs.ts` (setMobileTabIds). Any domain can import from these.
- `domain/_app/` — app-wide singletons: `system` (exchange rates, in `system.ts` + `system.types.ts`), `appState` (the `app_state` table, in `appState.ts`), `metadata` (db_metadata, in `metadata.ts` + `metadata.types.ts`), `export` (CSV export, in `export.ts` + `export.types.ts`). Not first-class domains. The `_app/mutations.ts` file owns the 7 mutations that target these (`setExchangeRate`, `deleteExchangeRate`, `setMobileTabIds`, `setDisplayCurrency`, `setBackupFrequency`, `setBackupRetention`, `reset`).

Plus the central types file:

- `domain/_args.ts` — the discriminated `Args` union keyed by action name. The wire contract for `/api/mutate`. `ActionName = keyof Args`; `ArgsFor<A> = Args[A]` is the per-action args shape. There is also `domain/_args.test.ts` — a union-shape smoke test that asserts the union is exhaustive and non-overlapping.

### `lib/db/mutate.ts` — the thin dispatcher

53 lines. Imports per-domain `handlers` maps and merges them into one `ALL` map. The `applyMutation(exec, action, args)` function looks up the action in `ALL` and dispatches.

**The only file that knows about all 74 actions.**

### The route layer (outside `lib/db/`)

`app/api/mutate/route.ts` calls `applyMutation(exec, action, args)`. It catches errors and uses `toWireError` (from `lib/i18n-error.ts`) to serialize I18nError to the wire shape. No other route file imports from `lib/db/`.

## Layer rules (enforced by ESLint)

| From | To | Allowed? |
|---|---|---|
| `core/*` | `core/*` | ✓ |
| `core/*` | `domain/*` | ✗ (no domain knowledge in core) |
| `domain/<x>/` | same domain (`<x>/`) | ✓ |
| `domain/<x>/` | `core/*` | ✓ |
| `domain/<x>/` | `domain/_shared/` | ✓ |
| `domain/<x>/` | `domain/_app/` | ✓ |
| `domain/<x>/` | `domain/_args.ts` | ✓ |
| `domain/<x>/` | sibling domain `domain/<y>/` | ⚠ — 5 known cross-domain deps use direct `queries` imports today (`accounts → accountGroups`, `transactions → attachments`, `budgets → budgetGroups`, `rules → counterparties`, `scheduled → counterparties`); a future PR introduces `domain/<x>/_deps.ts` re-exports to formalize this |
| `app/*`, `lib/*`, `components/*` | `lib/db/domain/<x>/types` | ✓ (type imports) |
| `app/*`, `lib/*`, `components/*` | `lib/db/domain/<x>/queries` | ✓ (read queries are public) |
| `app/*`, `lib/*`, `components/*` | `lib/db/domain/<x>/mutations` | ✗ — use the wire-level `@/lib/db/mutate.applyMutation` instead |
| `app/*`, `lib/*`, `components/*` | `lib/db/core/*` | ✓ |
| `app/*`, `lib/*`, `components/*` | `lib/db/mutate.ts` | ✓ (the public entry point) |

## Wire shape (preserved bit-for-bit from the pre-refactor code)

```
POST /api/mutate
  { action: "archiveAccount", args: { id: "acct-xyz" } }

→ withWrite((exec) => applyMutation(exec, body.action, body.args))
→ mutate.ts: looks up 'archiveAccount' in the merged ALL map
→ domain/accounts/mutations.ts: handlers.archiveAccount(exec, args)
→ domain/accounts/queries.ts → @/lib/db/queries/accounts → qArchiveAccount(exec, args.id)
→ SQL: UPDATE accounts SET is_active = 0, archived_at = datetime('now') ...

Response (success):
  { ...projectedState... }

Response (I18nError):
  { error: { code: "error.account.hasTransactions", params: {...}, message: "..." } }

Response (plain Error — internal bug):
  { error: "Budget not found" }  // (only the string; the message is the error message itself)
```

## Worked example: adding a new action to the `tags` domain

Scenario: add a `mergeTags(sourceId, targetId)` action that reassigns all transactions from `sourceId` to `targetId` and deletes the source. Tags currently has no `errors.ts` and no `mutations.test.ts`, so this example also shows how a domain graduates from a "SQL-only" shape to the full shape.

1. **Add the args type** to `domain/tags/types.ts`:
   ```ts
   export interface MergeTagsArgs { sourceId: string; targetId: string; }
   ```

2. **Add the row to the central Args map** in `domain/_args.ts`:
   ```ts
   import type { MergeTagsArgs, ... } from './tags/types';

   export type Args = {
     // ...existing entries...
     mergeTags: MergeTagsArgs;
   };
   ```
   `tsc` will fail at the dispatcher if you forget this — the `Handler<A>` constraint enforces that every action in `Args` is reachable from the merged `ALL` map.

3. **Add the query function** in `lib/db/queries/tags.ts` (the SQL home), then re-export it via `domain/tags/queries.ts`:
   ```ts
   // lib/db/queries/tags.ts
   export async function qMergeTags(exec: Exec, sourceId: string, targetId: string): Promise<void> {
     // BEGIN; UPDATE entry_tags SET tag_id = targetId WHERE tag_id = sourceId; DELETE FROM tags WHERE id = sourceId; COMMIT;
   }
   ```
   The `domain/tags/queries.ts` shim (`export * from '@/lib/db/queries/tags'`) auto-picks it up.

4. **Create `domain/tags/errors.ts`** (graduating from the "no errors" shape):
   ```ts
   export const TAG_ERROR_CODES = {
     notFound: 'error.notFound.tag',
     mergeSelf: 'error.tag.mergeSelf',
   } as const;
   ```

5. **Add the handler** in `domain/tags/mutations.ts`:
   ```ts
   import { I18nError } from '@/lib/i18n-error';
   import { TAG_ERROR_CODES } from './errors';
   import { qMergeTags } from './queries';

   export const handlers = {
     // ...existing handlers...
     mergeTags: async (exec, args: Args['mergeTags']) => {
       if (args.sourceId === args.targetId) {
         throw new I18nError(TAG_ERROR_CODES.mergeSelf, {}, 'Cannot merge a tag into itself');
       }
       await qMergeTags(exec, args.sourceId, args.targetId);
     },
   } satisfies Partial<{ [K in ActionName]: Handler<K> }>;
   ```

6. **Add a test** in `domain/tags/mutations.test.ts` (newly created):
   ```ts
   test('mergeTags reassigns and deletes', async () => { ... });
   test('mergeTags throws I18nError when source === target', async () => { ... });
   ```

That's it. The `mutate.ts` dispatcher auto-picks up the new handler from the merged `ALL` map. The `applyMutation` function exposed by the route handler makes it reachable via `/api/mutate`. No dispatcher change needed.

## Test counts (post-refactor)

- Total: 533 pass / 0 fail
- Per-domain tests: split across `domain/<x>/{queries,mutations}.test.ts` and `domain/_app/{system,export}.test.ts` (only 4 domains have `queries.test.ts`; 7 domains have `mutations.test.ts` — the rest are read-only or have no test surface yet)
- Central types: `lib/db/domain/_args.test.ts` (union-shape smoke test)
- Dispatcher tests: `lib/db/mutate.test.ts`
- Engine tests: `lib/db/{driver,migrate,pack,paths,seed,server,state,entries,import,metadata,autobackup,probe}.test.ts`
