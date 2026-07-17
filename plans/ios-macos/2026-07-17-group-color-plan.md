# Group color + Add-Group sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps. The design doc (`…-design.md`) is authoritative on rationale + migration facts; read it first. **This is the first shared-schema migration — do NOT improvise beyond the listed statements.**

**Goal:** `color TEXT` on both group tables (web + iOS, migrated), `createBudgetGroup/updateBudgetGroup` (+account twins) carry it, and Budgets' Add Group becomes a medium-detent sheet with name + swatches; group headers show a color dot.

## Global Constraints
- Branch stacks on #481. Builds: FinchApp (iOS) + FinchMac (macOS) `** BUILD SUCCEEDED **`; FinchCore `swift test` suite green; web `bun test lib` green (run from `frontend/`); `bun run typecheck` green. No `Co-Authored-By`. `packFormatVersion` untouched. PR → `feat/frontend`.

---

### Task 1: Web engine — schema + migration + queries

**Files:** `frontend/lib/db/core/schema.ts`, `frontend/lib/db/queries/budgetGroups.ts`, `frontend/lib/db/queries/accountGroups.ts` (locate exact name), `frontend/lib/db/domain/budgetGroups/types.ts` (+ account twin), any mutation arg types (`domain/_args.ts`) if they enumerate group args.

- [ ] **Step 1:** In both `CREATE TABLE … budget_groups/account_groups`, add `color      TEXT,` after `name` (nullable, matching other color columns). 
- [ ] **Step 2:** Add to the MIGRATIONS map (after the newest entry, mirroring its comment style):
```ts
  // Group colors (iOS-first UI; engine parity): nullable, additive.
  '2026-07-17T00:00:00Z': [
    'ALTER TABLE budget_groups ADD COLUMN color TEXT',
    'ALTER TABLE account_groups ADD COLUMN color TEXT',
  ],
```
Confirm how the runner derives the recorded latest version (if a constant mirrors the newest key, bump it — read the runner at `schema.ts:~688`).
- [ ] **Step 3:** Queries: both group query files — SELECTs gain `color`; `create…` INSERT gains `color` (bind `input.color ?? null`); `update…` gains `if (patch.color !== undefined) { sets.push('color = ?'); … }`. Types: `…Row`/`New…`/`…Patch` gain `color?: string | null` (Row: `color: string | null`).
- [ ] **Step 4:** `cd frontend && bun run typecheck && bun test lib` — ALL green (migration tests in `migrate.test.ts` may assert column lists; update only if they fail for the new column, keeping their intent).
- [ ] **Step 5:** Commit web files: `feat(db): color column on budget/account groups (+migration 2026-07-17)`.

---

### Task 2: iOS engine — schema + first evolution migration + domain + tests

**Files:** `ios/FinchCore/Sources/FinchCore/Storage/Schema.swift`, `Storage/Migrations.swift`, `Store/Domain/Groups.swift`, `Project/Models.swift`, `Project/Projections+State.swift`, tests in `ios/FinchCore/Tests/FinchCoreTests/`.

- [ ] **Step 1 (Schema):** add `color      TEXT,` after `name` in both group CREATEs; `static let version` → `"2026-07-17T00:00:00Z"`.
- [ ] **Step 2 (Migrations):** after the baseline registration add:
```swift
        // First post-baseline migration: group colors (web migration
        // 2026-07-17). Tolerant of duplicate columns — imported web packs may
        // already carry them while lacking GRDB's bookkeeping table.
        migrator.registerMigration("2026-07-17-group-color") { db in
            for table in ["budget_groups", "account_groups"] {
                do { try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN color TEXT") }
                catch { if !"\(error)".contains("duplicate column") { throw error } }
            }
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }
```
**Verify** (read, don't assume): the import path (`FinchStore` file-swap → reopen) calls `Migrations.runAll` on the imported file — if it doesn't, add it where the reopen happens and note it in the report.
- [ ] **Step 3 (Domain):** `Groups.create` — decode optional `color`, INSERT gains the column/bind; `Groups.update` cols map gains `"color": "color"`.
- [ ] **Step 4 (Projection/Model):** `GroupRow` gains `public var color: String?` (default nil in init — check `AccountGroupRow` typealias usages compile); the group readers (`Projection.accountGroups` / budget-group reader at `Projections+State.swift:~87`) SELECT + map `color`.
- [ ] **Step 5 (Tests):** FinchCore: (a) `createBudgetGroup` with color → projection returns it; (b) `updateBudgetGroup` color patch round-trips; (c) migration: build a DB via the OLD baseline only (craft: apply baseline schema minus color via raw SQL? — simpler: create a scratch `DatabaseQueue`, run full migrator, assert `PRAGMA table_info(budget_groups)` contains `color`; plus the duplicate-column tolerance: run the ALTER twice). Run `swift test` (full suite) — green, including the untouched 267+.
- [ ] **Step 6:** Build iOS. Commit engine files: `feat(ios-core): group color column — first post-baseline migration (2026-07-17), create/update/projection support`.

---

### Task 3: iOS UI — Add-Group sheet + color dots

**Files:** `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift`.

- [ ] **Step 1:** Replace the #481 Add-Group **alert** (state `addingGroup`/`newGroupName`, the `.alert`, `addGroup()`) with a sheet: keep `addingGroup`; `.sheet(isPresented: $addingGroup) { AddGroupSheet() .presentationDetents([.medium]) }`. New private struct in the same file:
```swift
/// Add Group — a medium-detent bottom sheet (same element family as Add Budget):
/// name + the shared 8-swatch palette. Creates via createBudgetGroup.
private struct AddGroupSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex: String? = nil
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name", text: $name)
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(TagPalette.hexes, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .secondary)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.primary.opacity(colorHex == hex ? 0.6 : 0), lineWidth: 2))
                                .onTapGesture { colorHex = (colorHex == hex ? nil : hex) }
                                .accessibilityLabel(Text(hex))
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Add Group")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    private func add() {
        var args: [String: JSONValue] = ["ledgerId": .string(store.activeLedgerId),
                                         "name": .string(name.trimmingCharacters(in: .whitespaces))]
        if let colorHex { args["color"] = .string(colorHex) }
        do { try store.apply(.createBudgetGroup, Args(args)); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}
```
(Check `TagPalette`/`Color(hex:)` visibility from this file — `Common/Color+Hex.swift`; adjust palette enum name to what exists.)
- [ ] **Step 2 (dots):** group-header Button label (normal list) and the reorder editor's group rows: before the name, `if let hex = groupColor(groupName)/… , let c = Color(hex: hex) { Circle().fill(c).frame(width: 8, height: 8) }` — resolve via `store.budgetGroups.first { $0.name == groupName }?.color` (normal list) / by gid (editor). Keep it subtle; no dot when color is nil.
- [ ] **Step 3:** Build iOS + macOS; re-run `BudgetReorderTests` (12/12). Commit: `feat(ios): Add Group bottom sheet (name + color) + group color dots`.

---

### Task 4: Verification (controller)
- [ ] Web: `bun test lib` + typecheck green (from Task 1 runs). iOS: full `swift test` green; both builds.
- [ ] Sim (ios-finch2): **upgrade path** — existing DB gets the migration on next launch (app still opens; `PRAGMA table_info` via sqlite3 shows `color`). Add Group sheet → create "Savings" with a color → appears in the Reorder editor with its dot; assign a budget → group renders on the page with the dot. **Pack round-trip:** export → import (Settings) still passes audit.
- [ ] Human pass: sheet feel (medium detent), swatch selection, dot rendering.

---

## Self-review notes
- Version stamps move together (web MIGRATIONS key = iOS migration id date = `Schema.version`); `ensureMetadataRow` re-stamp keeps db_metadata truthful. ✓
- Duplicate-column tolerance mirrors the web's idempotent `runMigrationStmt` for imported files. ✓
- Nullable column → no NOT NULL backfill, old packs import clean, old apps ignore it; `packFormatVersion` untouched. ✓
- New strings ("Add Group" exists from #481; "Color", "Group name", "Cancel"/"Add" exist) — verify at PR time; note any new ones for the zh batch. ✓
