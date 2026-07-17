# Task 1 report — Web engine: group color column

**Status:** DONE. Commit `5af3264a1a63f48a36b3728b59ec0760e7db9fb6` on `feat/ios-group-color` (no Co-Authored-By).

**Gates:** `bun run typecheck` green; `bun test lib` — 556 pass / 0 fail (49 files). No migration/schema test needed changes: `lib/db/migrate.test.ts` builds a stale DB without the group tables, but the runner's `isAlreadyAppliedError` swallows "no such table" on replay, so the new ALTERs are no-ops there and the test's intent (idempotent 06-05 ADD + version re-stamp) is untouched.

**Latest-version derivation (verify point):** `migrate()` (schema.ts:688) does NOT derive the latest version from the MIGRATIONS map keys. It reads the DB's recorded `db_metadata.schema_version`, replays map entries with keys strictly greater (lex/chronological sort), then stamps the exported constant `SCHEMA_VERSION` via `ensureMetadataRow`. So the constant is the recorded latest and had to be bumped: `SCHEMA_VERSION = '2026-07-17T00:00:00Z'` (was `'2026-06-14T00:00:00Z'`), matching the design doc's "version stamps move together" (= iOS `Schema.version` for Task 2). Without the bump, upgraded DBs would be stamped 2026-06-14 and re-replay the 07-17 entry forever (harmless but wrong).

**Changes:**
- `frontend/lib/db/core/schema.ts` — `color TEXT,` after `name` in both `account_groups`/`budget_groups` CREATEs; new MIGRATIONS entry `'2026-07-17T00:00:00Z'` (two ALTERs, comment per plan); `SCHEMA_VERSION` bumped.
- `frontend/lib/db/queries/budgetGroups.ts` + `accountGroups.ts` — SELECTs return `color` (null-safe map); create INSERT gains column binding `g.color ?? null`; update gains `patch.color !== undefined` branch; update `bind` widened to `(string | number | null)[]` so `color: null` clears.
- `frontend/lib/db/domain/budgetGroups/types.ts` + `accountGroups/types.ts` — `Row.color: string | null`; `New…`/`…Patch` gain `color?: string | null`.
- `frontend/lib/db/domain/_args.ts` — inline `createBudgetGroup` args gain `color?: string | null` (`createAccountGroup` uses `NewAccountGroup`, so it inherited it).
- `frontend/lib/db/domain/budgets/mutations.ts` + `accountGroups/mutations.ts` — create handlers pass `color: args.color ?? null` through to the queries (update handlers cast to Patch, so color flows automatically).
- `frontend/lib/store/budgetGroups/actions.ts` + `accountGroups/actions.ts` — optimistic create literals gain `color: null` (required by the now-stricter Row type; server projection replaces them after `/api/mutate`).

**Adaptations beyond the letter of the plan:** the two mutation-handler pass-throughs and the two store-literal `color: null` fixes (forced by making Row.color required, and needed for `createBudgetGroup` args to actually reach the INSERT). No blockers.

---

*Note: this file previously held the Task 1 report of the BudgetReorder plan (commit ae7f456); superseded by the group-color plan's Task 1.*
