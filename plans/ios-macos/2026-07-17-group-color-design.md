# Group color + Add-Group sheet (first shared-schema migration)

**Date:** 2026-07-17
**Status:** Design approved in discussion; plan written before any code (user-requested).
**Scope:** (1) Budget/account **groups gain a `color`** — a real schema column on BOTH platforms
(the first shared-schema change of this effort); (2) the Budgets **Add Group** flow upgrades from
the #481 name-alert to a **medium-detent bottom sheet** (the same element family as Add Budget:
a `.sheet`, with `presentationDetents([.medium])`) carrying name + an 8-swatch color picker;
(3) group headers (+ reorder-editor rows) show the color as a dot.
**Stacked on #481** (`feat/ios-budget-reorder-editor`) — rebases cleanly once that merges.

## Why a real column (not app_state)
Color is a first-class entity attribute with schema precedent — accounts, categories, tags,
scheduled all carry `color TEXT`. The app_state trick (#479) fits per-user/per-device prefs;
entity data belongs in the entity table, visible to the web's model and cleaned up with the row.

## Migration reality (researched, both sides)
- **Web:** `frontend/lib/db/core/schema.ts` has a dated `MIGRATIONS` map; the runner replays
  entries **strictly newer than** `db_metadata.schema_version`, and `runMigrationStmt` tolerates
  idempotent re-runs (e.g. duplicate column). Precedent: `'2026-06-05'` `ALTER TABLE accounts
  ADD COLUMN opening_balance_base`.
- **iOS:** `Migrations.swift` is a GRDB `DatabaseMigrator` with a **single baseline**
  (`baseline-2026-06-14` = full canonical `Schema` + metadata stamp). This feature registers the
  **first post-baseline migration** — and must ALSO add the column to the canonical schema string
  (fresh installs take the baseline path only).
- **Version stamps:** `Schema.version` (iOS) = `"2026-06-14T00:00:00Z"` and the web's recorded
  `schema_version` move together → both become `"2026-07-17T00:00:00Z"` (the new migration key).
- **Pack import:** packs carry the SQLite file + `schemaVersion` metadata. Old pack → new app:
  the migration runner upgrades it on import (web: by design; iOS: verify the import path runs
  `Migrations.runAll` on the swapped file, and make the ALTER idempotent-tolerant like the web's,
  since a web-authored file lacks GRDB's bookkeeping table). New pack → old app: additive nullable
  column is ignored by explicit-column SELECTs; `packFormatVersion` is unchanged (format, not
  schema). These verifications are explicit plan steps, not assumptions.

## Change surface

**Engine — web** (`frontend/lib/db/…`):
- `core/schema.ts`: `color TEXT` in both `budget_groups`/`account_groups` CREATEs + a
  `'2026-07-17T00:00:00Z'` MIGRATIONS entry with the two ALTERs.
- `queries/budgetGroups.ts` (+ account twin): SELECTs gain `color`; `NewBudgetGroup`/
  `BudgetGroupPatch` types + create/update queries gain optional `color`.
- Web UI adoption: out of scope (engine parity only).

**Engine — iOS** (`ios/FinchCore/…`):
- `Storage/Schema.swift`: `color TEXT` in both group CREATEs; `version` → 2026-07-17.
- `Storage/Migrations.swift`: register `"2026-07-17-group-color"` (two ALTERs, tolerant of
  duplicate-column on imported files).
- `Store/Domain/Groups.swift`: `create` accepts optional `color` (INSERT gains the column);
  `update` cols map gains `"color"`.
- `Project/Models.swift` `GroupRow` + `Projections+State.swift` group readers: `color: String?`.
- Tests: FinchCore — create-with-color round-trip; migration applies on a pre-migration DB;
  update patches color. (Parity fixtures: verify none pin the group column list.)

**UI — iOS:**
- `AddGroupSheet` (BudgetsTab-private): name field + the shared swatch row (reuse the palette
  UI pattern categories/tags use; `TagPalette`/`CategoryPalette` hexes exist) → `createBudgetGroup`
  with `color`; presented `.sheet` + `.presentationDetents([.medium])` — replaces #481's alert.
- Group header rows (Budgets normal list + reorder editor): a small `Circle().fill(hex)` dot
  before the name when color is set. (Accounts display: not yet — engine supports it; UI later.)
- Header long-press **Edit** stays name-only for now (color edit = natural follow-up).

## Out of scope
Web UI for colors; Accounts group-color UI; editing color from the header menu; recoloring
Manage-Groups-style admin (removed in #481); `packFormatVersion` bump (not needed).

## Testing
Unit (engine, both new paths) + both platform builds + web `bun test lib` (db suites) +
sim: fresh install (baseline path) and upgrade-in-place (migration path — reuse ios-finch2's
existing DB), Add Group sheet creates a colored group, dot renders, pack export→import survives.

## Addendum 2 (user feedback): empty groups render + budget picker in the sheet

The hide-empty rule read as a bug ("I add a group, it does not show"). Two changes:
(1) `budgetGroupsOrdered` now includes empty groups — a new group appears immediately;
(2) the Add Group sheet lists ALL budgets (current group shown as a caption) with checkmark
multi-select — chosen budgets are re-parented into the new group on create (sheet passes an
explicit `bgg-…` id so create + updateBudget(groupId) run in one pass).
