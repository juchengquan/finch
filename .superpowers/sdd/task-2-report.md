# Task 2 report — iOS engine: group color column + first post-baseline migration

**Status:** DONE
**Commit:** `5f957aa` — `feat(ios-core): group color column — first post-baseline migration (2026-07-17), create/update/projection support` (no Co-Authored-By; only ios/FinchCore files committed)

## What was done

1. **`Storage/Schema.swift`** — `color      TEXT,` added after `name` in BOTH `account_groups` and `budget_groups` CREATEs; `Schema.version` → `"2026-07-17T00:00:00Z"` (matches web `SCHEMA_VERSION` from Task 1).
2. **`Storage/Migrations.swift`** — registered `"2026-07-17-group-color"` after the baseline, exact code from the plan: duplicate-column-tolerant ALTERs over both tables + `Self.ensureMetadataRow(db)` re-stamp.
3. **`Store/Domain/Groups.swift`** — `create` decodes optional `color` and the INSERT gains the column/bind (applies to both account+budget group twins via the shared helper); `update` gains `if let colorV = patch["color"] { sets.append("color = ?"); bind.append(colorV.sqlBind) }` — note: the actual code uses explicit patch if-lets, not a cols map (plan adapted); `.null` patch clears the color (sqlBind → nil). Header comment updated ("name-only" → name/color/sortOrder).
4. **`Project/Models.swift`** — `GroupRow` gains `public var color: String?`, init default `nil` (existing call sites + `AccountGroupRow` typealias compile unchanged). **`Project/Projections+State.swift`** — both group readers (`Projection.accountGroups` / `Projection.budgetGroups`) funnel through ONE private `groupRows(...)` helper (line ~95); its SELECT + map gained `color`. The only other `FROM budget_groups` SELECT (`budgetGroupNames`, id→name map) doesn't build GroupRow — untouched by design.
5. **Tests** — new `Tests/FinchCoreTests/GroupColorTests.swift` (4 tests, TestSeed idioms): create-with-color round-trip (+ nil default), update patch round-trip (+ null clears), account-group twin, and migrator test (PRAGMA table_info contains `color` in both tables, db_metadata re-stamped to 2026-07-17, tolerant-ALTER idiom run a second time doesn't throw).

## Import-path verify finding (step 3)

**`Migrations.runAll` IS already called on the imported DB — no change needed.** `FinchApp/Sources/FinchApp/FinchStore+ImportExport.swift:28`: `loadPack` step 3 opens the staged (extracted) DB and runs `try Migrations.runAll(on: stagedQueue)` BEFORE the audit gate and the atomic swap — so the file that gets swapped in is already migrated. The D7 force-import path (`forceImportCurrentPack`) reuses that same retained, already-migrated staged file. The reopen after swap (`swapInAndProject`) therefore correctly does not re-run migrations. This is exactly the case the duplicate-column tolerance covers: a web-authored pack already carries `color` but lacks GRDB's bookkeeping table, so the GRDB migrator replays both migrations on it and the ALTER must swallow "duplicate column".

## Test/build results

- `swift test` (full FinchCore suite): **271 tests, 0 failures** (was 267; +4 new).
- `xcodegen generate && xcodebuild … FinchApp … iPhone 17 Pro`: **BUILD SUCCEEDED**.

## Adaptations (plan → reality)

- `Groups.update` has no "cols map" (plan wording) — explicit patch if-lets; added the color branch in that idiom.
- `SchemaTests.test_schemaVersionIsSet` pinned `"2026-06-14T00:00:00Z"`; updated the pin to `"2026-07-17T00:00:00Z"` keeping its intent (constant matches the shared web version) — this was the only pre-existing test needing a touch.
- Fresh-install path note: the baseline now creates `color` directly, so the post-baseline migration's ALTER hits "duplicate column" even on fresh DBs — intentionally absorbed by the tolerance catch (and exercised by every `Migrations.runAll` in the suite).
- Note: this file previously held a report from an earlier plan's task numbering (Reorder editor, commit f329d47); overwritten per instructions.

## Blockers

None.
