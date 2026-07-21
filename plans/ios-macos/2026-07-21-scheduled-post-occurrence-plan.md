# Posting a scheduled occurrence — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** "Post now" on a Scheduled occurrence records that specific occurrence and its badge
updates — via an edit sheet, with the link tracked explicitly so the badge stays right even if
the user changes the date.

**Architecture:** A new nullable `entries.occurrence_date` column links a transaction to the
occurrence it fulfils. `Selectors.scheduledPostedMap` keys on it, falling back to the
transaction date when NULL — which is exactly today's behaviour, so no backfill is needed.
`postScheduled` gains optional `date`/`occurrenceDate`; `addTransaction` gains optional
`sourceTemplateId`/`occurrenceDate` (closing an asymmetry — `addTransfer` already has the
former). The UI routes most templates into a prefilled `AddTransactionSheet`; split-income
templates keep the silent path because the sheet cannot express N accounts.

**Tech Stack:** Swift 6 / SwiftUI / GRDB (`FinchCore` + `FinchApp`), TypeScript / SQLite
(`frontend/lib/db`), XCTest, Bun.

**Design doc:** `plans/ios-macos/2026-07-21-scheduled-post-occurrence-design.md`

## Global Constraints

- **The web leads the schema.** `Schema.swift` is the web's interpolated `SCHEMA` copied
  **byte-for-byte**; `Schema.version` must equal the web `SCHEMA_VERSION`. Change
  `frontend/lib/db/core/entries-schema.ts` first, then mirror into Swift.
- **New `SCHEMA_VERSION` is `2026-07-22T00:00:00Z`.** `2026-07-21T00:00:00Z` is already taken
  by the budget-match columns.
- **Migrations must be additive, nullable, and duplicate-tolerant** — imported web packs may
  already carry the column while lacking GRDB's bookkeeping table. Follow the
  `2026-07-21-budget-match-columns` precedent exactly.
- **New action arguments are OPTIONAL.** Absent ⇒ today's behaviour byte-for-byte, so web
  parity holds.
- **Build both** `FinchApp` (simulator) and `FinchMac` before every PR. `xcodegen generate`
  after adding any file. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Never call `Money.format` in a view**; use the privacy-aware `store.display*` helpers.
- **`store.wallToday`, not `store.today`**, for "has this happened yet" questions.
- **`finchSectionHeader` takes `LocalizedStringKey`**, and the first section after a type
  caption carries no header (`ios/CLAUDE.md`).
- **Measure UI with `idb ui describe-all`** (frames in points), not screenshots.

---

# PR 1 — engine, schema, and the calendar entry point

Fixes the reported bug end-to-end. Tasks 1–7.

### Task 1: Schema column + migration, both sides

**Files:**
- Modify: `frontend/lib/db/core/entries-schema.ts:21`
- Modify: `frontend/lib/db/core/schema.ts:438` (version), `:628` (MIGRATIONS)
- Modify: `ios/FinchCore/Sources/FinchCore/Storage/Schema.swift:12` (version), `:339` (DDL)
- Modify: `ios/FinchCore/Sources/FinchCore/Storage/Migrations.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/SchemaTests.swift:10`,
  `ios/FinchCore/Tests/FinchCoreTests/MigrationsTests.swift`

**Interfaces:**
- Produces: `entries.occurrence_date TEXT` (nullable) available to every later task.

- [ ] **Step 1: Add the column to the web DDL**

In `frontend/lib/db/core/entries-schema.ts`, directly after the `source_template_id TEXT,`
line (21):

```sql
  -- The scheduled occurrence this entry fulfils (yyyy-MM-dd), when it was posted
  -- from a template. NULL for everything else. Lets a transaction dated "when I
  -- actually paid" still resolve the occurrence it was due on.
  occurrence_date    TEXT,
```

- [ ] **Step 2: Bump the web version and add the migration**

`frontend/lib/db/core/schema.ts:438`:

```ts
export const SCHEMA_VERSION = '2026-07-22T00:00:00Z';
```

In `MIGRATIONS`, after the `'2026-07-21T00:00:00Z'` entry:

```ts
    // Link a posted transaction to the scheduled occurrence it fulfils, so the
    // occurrence resolves even when the transaction carries a different date.
    '2026-07-22T00:00:00Z': [
      'ALTER TABLE entries ADD COLUMN occurrence_date TEXT',
    ],
```

- [ ] **Step 3: Mirror into Swift, byte-for-byte**

`Schema.swift:12` → `public static let version = "2026-07-22T00:00:00Z"`, and insert the same
two comment lines + `occurrence_date    TEXT,` after `source_template_id TEXT,` (line 339).
Column alignment must match the web file exactly.

- [ ] **Step 4: Register the native migration**

In `Migrations.swift`, after `2026-07-21-budget-match-columns`:

```swift
        // Scheduled occurrence link (web migration 2026-07-22). Additive +
        // nullable; tolerant of duplicate columns (imported web packs may already
        // carry it).
        migrator.registerMigration("2026-07-22-entry-occurrence-date") { db in
            do { try db.execute(sql: "ALTER TABLE entries ADD COLUMN occurrence_date TEXT") }
            catch { if !"\(error)".contains("duplicate column") { throw error } }
            try Self.ensureMetadataRow(db)   // re-stamp schema_version
        }
```

- [ ] **Step 5: Update the version tripwire and add a migration test**

`SchemaTests.swift:10` → `XCTAssertEqual(Schema.version, "2026-07-22T00:00:00Z")`.

Add to `MigrationsTests.swift`:

```swift
    func test_occurrenceDateColumn_isAddedAndIdempotent() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(q)
        try Migrations.runAll(q)          // replay must not throw
        try q.read { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(entries)").map { $0["name"] as String }
            XCTAssertTrue(cols.contains("occurrence_date"))
        }
    }
```

- [ ] **Step 6: Run tests**

Run: `cd ios && swift test`
Expected: PASS, including the two above.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/db/core/entries-schema.ts frontend/lib/db/core/schema.ts \
        ios/FinchCore/Sources/FinchCore/Storage/ ios/FinchCore/Tests/FinchCoreTests/
git commit -m "feat(schema): entries.occurrence_date links a posting to its scheduled occurrence"
```

---

### Task 2: Carry `occurrenceDate` through the entry write path

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Entries.swift` (input structs ~112–135 and
  ~425–445; INSERT ~395)
- Test: `ios/FinchCore/Tests/FinchCoreTests/EntriesOccurrenceTests.swift` (create)

**Interfaces:**
- Consumes: the column from Task 1.
- Produces: `Entries.Input.occurrenceDate: String?` and the same on the simple-post input;
  persisted to `entries.occurrence_date`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/EntriesOccurrenceTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class EntriesOccurrenceTests: XCTestCase {
    func test_postSimple_persistsOccurrenceDate() throws {
        let q = try TestDB.seeded()          // existing helper used by ApplyTests
        try q.write { db in
            try Entries.postSimple(db, .init(ledgerId: "personal", accountId: "a1", amount: -10,
                                             date: "2026-07-21", description: "Gym",
                                             categoryId: nil, kind: .expense,
                                             sourceTemplateId: "s1", occurrenceDate: "2026-07-15"))
        }
        try q.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(row?["occurrence_date"], "2026-07-15")
        }
    }

    func test_postSimple_withoutOccurrenceDate_leavesItNull() throws {
        let q = try TestDB.seeded()
        try q.write { db in
            try Entries.postSimple(db, .init(ledgerId: "personal", accountId: "a1", amount: -10,
                                             date: "2026-07-21", description: "Manual",
                                             categoryId: nil, kind: .expense))
        }
        try q.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT occurrence_date FROM entries WHERE description = 'Manual'")
            XCTAssertNil(row?["occurrence_date"] as String?)
        }
    }
}
```

If `TestDB.seeded()` does not exist under that name, use whatever fixture helper `ApplyTests.swift`
uses — do not invent a new one.

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd ios && swift test --filter EntriesOccurrenceTests`
Expected: FAIL — `occurrenceDate` is not a parameter.

- [ ] **Step 3: Add the field to both input structs**

In `Entries.swift`, beside `public var sourceTemplateId: String?` in **both** input structs
(~line 119 and ~line 431), add:

```swift
        /// The scheduled occurrence this entry fulfils (yyyy-MM-dd). NULL unless posted
        /// from a template. Lets the occurrence resolve even when `date` differs.
        public var occurrenceDate: String?
```

Add `occurrenceDate: String? = nil` to each `init`, defaulted so every existing call site
compiles unchanged, and assign it alongside `sourceTemplateId`.

- [ ] **Step 4: Persist it**

In the INSERT (~line 395) add `occurrence_date` to the column list and one more `?` to VALUES,
passing `e.occurrenceDate` immediately after `e.sourceTemplateId`. Also thread it through the
`postSimple` wrapper (~line 505) and the struct-to-struct hand-off at ~line 454.

- [ ] **Step 5: Run tests**

Run: `cd ios && swift test`
Expected: PASS — the two new tests, and all pre-existing ones unchanged.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Entries.swift ios/FinchCore/Tests/
git commit -m "feat(core): carry occurrenceDate through the entry write path"
```

---

### Task 3: `postScheduled` accepts a date; `generateDue` stamps the link

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Scheduled.swift` (`post` ~28–75,
  `generateDue` ~77–125)
- Modify: `frontend/lib/db/domain/_args.ts:178`
- Test: `ios/FinchCore/Tests/FinchCoreTests/ScheduledPostTests.swift` (create)

**Interfaces:**
- Consumes: `Entries.Input.occurrenceDate` (Task 2).
- Produces: `postScheduled { templateId, date?, occurrenceDate? }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import GRDB
@testable import FinchCore

final class ScheduledPostTests: XCTestCase {
    func test_post_withExplicitDate_usesItForBothColumns() throws {
        let q = try TestDB.seeded()
        try q.write { db in
            try Apply.apply(db, .postScheduled, Args([
                "templateId": .string("s1"), "date": .string("2026-07-15"),
            ]))
        }
        try q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT date, occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(r?["date"], "2026-07-15")
            XCTAssertEqual(r?["occurrence_date"], "2026-07-15")
        }
    }

    func test_post_withSeparateOccurrenceDate_keepsThemDistinct() throws {
        let q = try TestDB.seeded()
        try q.write { db in
            try Apply.apply(db, .postScheduled, Args([
                "templateId": .string("s1"), "date": .string("2026-07-21"),
                "occurrenceDate": .string("2026-07-15"),
            ]))
        }
        try q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT date, occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(r?["date"], "2026-07-21")
            XCTAssertEqual(r?["occurrence_date"], "2026-07-15")
        }
    }

    /// Parity guard: no date argument must behave exactly as before.
    func test_post_withoutDate_stampsTodayAndSetsOccurrenceToIt() throws {
        let q = try TestDB.seeded()
        try q.write { db in
            try Apply.apply(db, .postScheduled, Args(["templateId": .string("s1")]))
        }
        try q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT date, occurrence_date FROM entries WHERE source_template_id = 's1'")
            XCTAssertEqual(r?["date"] as String?, r?["occurrence_date"] as String?)
        }
    }
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd ios && swift test --filter ScheduledPostTests`
Expected: FAIL — the args are ignored, `occurrence_date` is NULL.

- [ ] **Step 3: Accept the arguments**

In `Scheduled.post`, replace the decode + date lines (~29 and ~40):

```swift
        struct A: Decodable { let templateId: String; let date: String?; let occurrenceDate: String? }
        let a = try args.to(A.self)
        let templateId = a.templateId
```

```swift
        // Explicit date wins; otherwise today (unchanged legacy behaviour). The
        // occurrence defaults to the posting date, so a plain post still resolves
        // its own cell.
        let date = a.date ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let occurrenceDate = a.occurrenceDate ?? date
```

Pass `occurrenceDate` into `postSingle`, `Entries.postTransfer`, and the split loop — every
`sourceTemplateId: templateId` call in this function gains `occurrenceDate: occurrenceDate`.
Widen `postSingle`'s own signature (~19) to take it.

- [ ] **Step 4: Stamp it in `generateDue` too**

In the `for date in dates` loops (~106 and ~118), pass `occurrenceDate: date` alongside
`sourceTemplateId`. Both posting paths now agree.

- [ ] **Step 5: Mirror the web arg type**

`frontend/lib/db/domain/_args.ts:178`:

```ts
  postScheduled: { templateId: string; date?: string; occurrenceDate?: string };
```

Apply the same defaulting in the web's `postScheduled` mutation and stamp `occurrence_date` in
its `generateDue`, so data written by either front-end resolves in both.

- [ ] **Step 6: Run tests**

Run: `cd ios && swift test` and `cd frontend && bun test lib`
Expected: PASS both.

- [ ] **Step 7: Commit**

```bash
git commit -am "feat(core): postScheduled takes an explicit date + occurrence link"
```

---

### Task 4: `addTransaction` / `addTransfer` accept the template link

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift` (`AddInput` 193–210,
  `addTransactionReturningId` 219+)
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transfers.swift:62`
- Modify: `frontend/lib/db/domain/transactions/types.ts` (`AddInput`), `frontend/lib/db/domain/_args.ts`
- Test: extend `ios/FinchCore/Tests/FinchCoreTests/ScheduledPostTests.swift`

**Interfaces:**
- Produces: `addTransaction { …, sourceTemplateId?, occurrenceDate? }`. **Without this the whole
  feature is inert** — a sheet-saved transaction would carry no template link and the badge
  would never flip.

- [ ] **Step 1: Write the failing test**

```swift
    func test_addTransaction_canCarryTheTemplateLink() throws {
        let q = try TestDB.seeded()
        try q.write { db in
            try Apply.apply(db, .addTransaction, Args([
                "ledgerId": .string("personal"), "accountId": .string("a1"),
                "amount": .double(-40), "merchant": .string("Gym"),
                "date": .string("2026-07-21"),
                "sourceTemplateId": .string("s1"), "occurrenceDate": .string("2026-07-15"),
            ]))
        }
        try q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT source_template_id, occurrence_date FROM entries WHERE description = 'Gym'")
            XCTAssertEqual(r?["source_template_id"], "s1")
            XCTAssertEqual(r?["occurrence_date"], "2026-07-15")
        }
    }
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd ios && swift test --filter test_addTransaction_canCarryTheTemplateLink`
Expected: FAIL — both columns NULL (the args are silently dropped).

- [ ] **Step 3: Add the fields**

`AddInput` (Transactions.swift:193–210) gains:

```swift
        let sourceTemplateId: String?
        let occurrenceDate: String?
```

Forward both into every `Entries.Input` / `postSimple` construction inside
`addTransactionReturningId` (both the same-currency and foreign-currency branches). In
`Transfers.swift:62` add `let occurrenceDate: String?` beside the existing `sourceTemplateId`
and forward it at ~line 70.

- [ ] **Step 4: Mirror the web types**

Add both optional fields to the web `AddInput` (`frontend/lib/db/domain/transactions/types.ts`)
and forward them in the web's add-transaction mutation.

- [ ] **Step 5: Run tests**

Run: `cd ios && swift test` and `cd frontend && bun test lib`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(core): addTransaction/addTransfer can carry the scheduled template link"
```

---

### Task 5: Read path — `Tx.occurrenceDate` and the resolution rule

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift:25`
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projection.swift:84`
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Forecast.swift:250`
- Test: `ios/FinchCore/Tests/FinchCoreTests/ScheduledPostedMapTests.swift` (create)

**Interfaces:**
- Produces: `Tx.occurrenceDate: String?`; `scheduledPostedMap` keyed on
  `occurrenceDate ?? date`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FinchCore

final class ScheduledPostedMapTests: XCTestCase {
    /// `Tx` has a wide memberwise init; every parameter not named here is defaulted.
    /// If a required one has no default, pass the same value the existing
    /// `SelectorsTests` helpers use — do not introduce a new fixture shape.
    private func tx(_ id: String, date: String, occurrence: String?, template: String?) -> Tx {
        Tx(id: id, accountId: "a1", date: date, amount: -40, description: "Gym",
           sourceTemplateId: template, occurrenceDate: occurrence)
    }

    /// The bug: a transaction dated later must resolve the occurrence it fulfils.
    func test_prefersOccurrenceDateOverTransactionDate() {
        let map = Selectors.scheduledPostedMap([tx("e1", date: "2026-07-21", occurrence: "2026-07-15", template: "gym")])
        XCTAssertNotNil(map["gym|2026-07-15"])
        XCTAssertNil(map["gym|2026-07-21"])
    }

    /// No backfill: historical rows have NULL and must behave exactly as before.
    func test_fallsBackToTransactionDateWhenNull() {
        let map = Selectors.scheduledPostedMap([tx("e1", date: "2026-07-15", occurrence: nil, template: "gym")])
        XCTAssertNotNil(map["gym|2026-07-15"])
    }

    func test_ignoresTransactionsWithNoTemplate() {
        XCTAssertTrue(Selectors.scheduledPostedMap([tx("e1", date: "2026-07-15", occurrence: nil, template: nil)]).isEmpty)
    }
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd ios && swift test --filter ScheduledPostedMapTests`
Expected: FAIL to compile — `Tx` has no `occurrenceDate`.

- [ ] **Step 3: Add the field and read it**

`Models.swift:25`, beside `sourceTemplateId`:

```swift
    public var occurrenceDate: String?
```

Add `occurrenceDate: String? = nil` to `Tx.init` (~36) and assign it (~42). In
`Projection.swift:84`, beside `sourceTemplateId: r["source_template_id"]`:

```swift
            occurrenceDate: r["occurrence_date"],
```

- [ ] **Step 4: Change the resolution rule**

`Forecast.swift:252`:

```swift
        // Key on the occurrence the entry FULFILS, not the day it was recorded —
        // they differ when the user posts a missed item on a later date. NULL
        // falls back to `date`, which is the pre-2026-07-22 behaviour, so
        // historical generateDue postings still resolve with no backfill.
        for t in txns { if let s = t.sourceTemplateId { out["\(s)|\(t.occurrenceDate ?? t.date)"] = (t.pending ?? false) } }
```

Update the doc comment above it to match (it currently describes only the date keying).

- [ ] **Step 5: Run tests**

Run: `cd ios && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(core): resolve scheduled occurrences by their explicit link"
```

---

### Task 6: Give `postScheduled` a write-parity gate

**Files:**
- Modify: `frontend/scripts/export-fixtures.ts:493`
- Regenerate: `ios/FinchCore/Tests/ParityTests/Fixtures/writeparity/sequence.json`

**Interfaces:**
- Consumes: the `date` argument from Task 3.

Context: `postScheduled` has **never** had a parity gate — it is excluded from `WRITE_SEQUENCE`
with the note *"it stamps `new Date()`, so it can't be reproduced offline"*. Task 3 removes that
reason.

- [ ] **Step 1: Add it to `WRITE_SEQUENCE`**

Replace the exclusion comment at `:493` and add, after the `addScheduledSplit` entries (so the
split path is exercised too):

```ts
  // postScheduled with a PINNED date — reproducible offline now that the action
  // takes an explicit date (2026-07-22), so it finally gets a parity gate.
  { action: 'postScheduled', args: { templateId: 's2', date: '2026-05-20' } },
  { action: 'postScheduled', args: { templateId: 's2', date: '2026-05-21', occurrenceDate: '2026-05-18' } },
```

Use a template id that exists in the fixture seed and is **not** `s1` (which the split CRUD
above mutates). Verify the id against the seed before running.

- [ ] **Step 2: Regenerate ONLY the write-parity fixture**

Run: `cd frontend && bun scripts/export-fixtures.ts`

Then **revert everything except `writeparity/sequence.json`** — the audit / projection /
round-trip fixtures otherwise change by `datetime('now')` noise alone:

```bash
git checkout -- ios/FinchCore/Tests/ParityTests/Fixtures/audit \
                ios/FinchCore/Tests/ParityTests/Fixtures/projection
git status --short   # expect ONLY writeparity/sequence.json modified
```

- [ ] **Step 3: Run the parity gate**

Run: `cd ios && swift test --filter WriteParityTests`
Expected: PASS — the Swift chokepoint reproduces the web's postings exactly.

- [ ] **Step 4: Commit**

```bash
git add frontend/scripts/export-fixtures.ts ios/FinchCore/Tests/ParityTests/Fixtures/writeparity/sequence.json
git commit -m "test(parity): cover postScheduled now that it takes an explicit date"
```

---

### Task 7: Calendar "Post now" opens a prefilled sheet

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledPostRouting.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift:12, :267`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift:139, :194`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift` (save path ~434)
- Test: `ios/FinchApp/Tests/FinchAppTests/ScheduledPostRoutingTests.swift` (create)

**Interfaces:**
- Consumes: everything above.
- Produces: `ScheduledPostRouting.route(template:splitCount:) -> PostRoute`.

- [ ] **Step 1: Write the failing test for the pure routing decision**

Create `ios/FinchApp/Tests/FinchAppTests/ScheduledPostRoutingTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

/// Which templates the edit sheet can faithfully represent. Split-income templates
/// fan out across MULTIPLE ACCOUNTS; the sheet's splits are categories within ONE
/// transaction — a different concept — so those keep the silent engine path.
final class ScheduledPostRoutingTests: XCTestCase {
    private func t(amount: Double?, type: String = "expense") -> ScheduledTemplate {
        ScheduledTemplate(id: "s1", name: "Gym", description: nil, type: type, amount: amount,
                          frequency: "monthly", dayOfMonth: 15, weekDay: nil, accountId: "a1",
                          fromAccountId: nil, startDate: "2026-01-15", endDate: nil,
                          nextRun: "", maxExecutions: nil, installmentTotal: nil, installmentPaid: nil)
    }

    func test_simpleTemplate_opensSheet() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: -40), splitCount: 0), .sheet)
    }

    func test_variableAmountTemplate_opensSheet() {   // today this ERRORS in the engine
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: nil), splitCount: 0), .sheet)
    }

    func test_transferTemplate_opensSheet() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: -40, type: "transfer"), splitCount: 0), .sheet)
    }

    func test_splitIncomeTemplate_staysSilent() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: 4200, type: "income"), splitCount: 2), .silent)
    }

    func test_incomeWithoutSplits_opensSheet() {
        XCTAssertEqual(ScheduledPostRouting.route(t(amount: 4200, type: "income"), splitCount: 0), .sheet)
    }
}
```

- [ ] **Step 2: Run it, confirm it fails**

Run the `FinchApp` scheme test action filtered to `ScheduledPostRoutingTests`.
Expected: FAIL — no such type.

- [ ] **Step 3: Implement the routing**

Create `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledPostRouting.swift`:

```swift
import Foundation
import FinchCore

/// Where a "Post now" tap should go. Most templates open a prefilled edit sheet so
/// the user can confirm the date and amount; split-income templates cannot be
/// represented there (their splits fan out across ACCOUNTS, while the sheet's
/// splits are categories inside one transaction), so they keep the silent engine
/// path — which posts every split correctly.
enum PostRoute { case sheet, silent }

enum ScheduledPostRouting {
    static func route(_ template: ScheduledTemplate, splitCount: Int) -> PostRoute {
        template.type == "income" && splitCount > 0 ? .silent : .sheet
    }
}
```

- [ ] **Step 4: Run the test**

Expected: PASS (5/5).

- [ ] **Step 5: Thread the occurrence date through the calendar**

`ScheduledCalendarView.swift:12` → `var onPost: (ScheduledTemplate, String) -> Void`, and `:267`
→ `Button { onPost(t, date) }`. The `date` is already in scope in `occurrenceRow`.

- [ ] **Step 6: Route it in `ScheduledTab`**

Replace `postNow` (`:194`) with an occurrence-aware version, and add the sheet state:

```swift
    /// `.sheet(item:)` needs Identifiable, and a tuple can't conform.
    struct PostPrefill: Identifiable {
        let template: ScheduledTemplate
        let occurrence: String
        var id: String { "\(template.id)|\(occurrence)" }
    }

    @State private var postPrefill: PostPrefill?

    private func postNow(_ t: ScheduledTemplate, occurrence: String) {
        let splits = store.scheduledSplitCount(templateId: t.id)
        switch ScheduledPostRouting.route(t, splitCount: splits) {
        case .sheet:
            postPrefill = PostPrefill(template: t, occurrence: occurrence)
        case .silent:
            do {
                try store.apply(.postScheduled, Args([
                    "templateId": .string(t.id), "date": .string(occurrence),
                ]))
            } catch { errorMessage = i18nMessage(error) }
        }
    }
```

Wire `onPost: postNow` (`:139`) and present the sheet:

```swift
        .sheet(item: $postPrefill) { p in
            AddTransactionSheet(prefill: store.txPrefill(for: p.template, occurrence: p.occurrence))
        }
```

The `id` deliberately combines template **and** occurrence: posting two occurrences of the same
template in one sitting must re-present the sheet, which a template-only id would suppress.

- [ ] **Step 7: Build a prefill `Tx` from the template**

Add `store.txPrefill(for:occurrence:)` to `FinchStore+ViewHelpers.swift`, returning a `Tx` with
the template's account, amount (sign per type), description, category, `sourceTemplateId`, the
occurrence as **both** `date` and `occurrenceDate`. A nil amount leaves the field empty — that
is the variable-amount case the sheet now fixes.

Also add `store.scheduledSplitCount(templateId:)` (a `COUNT(*)` over `scheduled_splits`) if the
store does not already expose the splits.

- [ ] **Step 8: Forward the link when the sheet saves**

In `AddTransactionSheet.save()` (~434), when `prefill?.sourceTemplateId` is non-nil, add to the
`addTransaction` / `addTransfer` args:

```swift
        if let tid = prefill?.sourceTemplateId {
            args["sourceTemplateId"] = .string(tid)
            if let occ = prefill?.occurrenceDate { args["occurrenceDate"] = .string(occ) }
        }
```

- [ ] **Step 9: Re-check the installment cap on this path**

The cap lives in `Scheduled.post` and the sheet bypasses it. Before presenting the sheet in
`postNow`, if `t.installmentTotal != nil` and the confirmed count has reached it, set
`errorMessage` from `error.scheduled.installmentDone` and do **not** present. Reuse the engine's
message key so the copy matches.

- [ ] **Step 10: Build both targets and verify on the simulator**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" build
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS'
```

Then reproduce the original report: Scheduled → tap a past day with an occurrence → context-menu
**Post now** → the sheet opens with the occurrence's date → save → the badge flips `missed` →
`done`. Confirm with `idb ui describe-all`, not a screenshot.

- [ ] **Step 11: Commit**

```bash
git commit -am "fix(ios): Post now records the occurrence you tapped, via a prefilled sheet"
```

---

**End of PR 1.** Open it against `feat/frontend` with before/after `describe-all` output for the
badge. PR 2 is independent and can wait for review.

---

# PR 2 — the remaining entry points

Tasks 8–10. Depends on PR 1 being merged.

### Task 8: "Resume" occurrence selector

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Forecast.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/ResumeOccurrenceTests.swift` (create)

**Interfaces:**
- Produces: `Selectors.resumeOccurrence(template:posted:today:) -> String?` — the earliest
  occurrence with no posting, else the next occurrence at or after `today`, else nil.

- [ ] **Step 1: Write the failing test**

```swift
final class ResumeOccurrenceTests: XCTestCase {
    // Template due the 8th and 15th monthly; today is the 21st; nothing posted.
    func test_picksOldestUnresolvedFirst() {
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly8th, posted: [:], today: "2026-07-21"),
                       "2026-07-08")
    }

    func test_skipsResolvedOccurrences() {
        let posted = ["gym|2026-07-08": false]
        XCTAssertEqual(Selectors.resumeOccurrence(template: monthly8th, posted: posted, today: "2026-07-21"),
                       "2026-08-08")
    }

    func test_fallsForwardWhenNothingIsMissed() {
        let posted = ["gym|2026-07-08": false, "gym|2026-06-08": false]
        let r = Selectors.resumeOccurrence(template: monthly8th, posted: posted, today: "2026-07-21")
        XCTAssertEqual(r, "2026-08-08")
        XCTAssertTrue(r! >= "2026-07-21")
    }
}
```

Build `monthly8th` with the same `ScheduledTemplate` initialiser used in Task 7's test.

- [ ] **Step 2: Run it, confirm it fails**

Run: `cd ios && swift test --filter ResumeOccurrenceTests`
Expected: FAIL — no such function.

- [ ] **Step 3: Implement it**

```swift
    /// The occurrence a bare "Post now" should act on: catch up oldest-first, the
    /// same order generateDue uses, then fall forward to the next due one. Bounded
    /// by a ~400-day lookback/horizon so yearly templates resolve.
    public static func resumeOccurrence(template: ScheduledTemplate,
                                        posted: [String: Bool],
                                        today: String) -> String? {
        // ~400 days covers a yearly template. Parsed and formatted inside ONE
        // calendar, so the timezone is unobservable — do not "fix" it to local
        // (ios/CLAUDE.md, civil-date convention).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = cal.date(from: DateComponents(
            year: Int(today.prefix(4)), month: Int(today.dropFirst(5).prefix(2)),
            day: Int(today.dropFirst(8).prefix(2)))) ?? Date()
        let h = cal.dateComponents([.year, .month, .day],
                                   from: cal.date(byAdding: .day, value: 400, to: base) ?? base)
        let horizon = String(format: "%04d-%02d-%02d", h.year ?? 0, h.month ?? 1, h.day ?? 1)
        let all = occurrencesUpTo(template, horizon)
        if let missed = all.first(where: { $0 < today && posted["\(template.id)|\($0)"] == nil }) {
            return missed
        }
        return all.first { $0 >= today && posted["\(template.id)|\($0)"] == nil }
    }
```

Reuse the horizon computation from `scheduledNextRun` (`ScheduledTab.swift:262`) rather than
duplicating the date math — move it into `Forecast.swift` if that is cleaner, but do **not**
change its UTC calendar (it parses and formats inside one calendar, so the zone is unobservable
— see `ios/CLAUDE.md`).

- [ ] **Step 4: Run tests**

Run: `cd ios && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(core): resumeOccurrence picks up where the schedule left off"
```

---

### Task 9: List and detail entry points open the sheet

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift:84, :88`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledDetailView.swift:34, :110`

- [ ] **Step 1: Route the three template-only entry points**

Each currently calls `postNow(t)`. Change to resolve the occurrence first:

```swift
    private func postNow(_ t: ScheduledTemplate) {
        let posted = Selectors.scheduledPostedMap(store.txns)
        guard let occ = Selectors.resumeOccurrence(template: t, posted: posted, today: store.wallToday) else {
            errorMessage = "Nothing left to post for \"\(t.name)\"."   // localize
            return
        }
        postNow(t, occurrence: occ)     // the Task 7 router
    }
```

`ScheduledDetailView` needs the same sheet presentation as `ScheduledTab` — extract the
`.sheet(item:)` + `PostPrefill` into a small shared modifier rather than copying it.

- [ ] **Step 2: Note the swipe-action consequence**

`:84` is a swipe quick-action and now presents a modal. That was chosen deliberately; add a
one-line comment saying so, so the next reader does not "fix" it back.

- [ ] **Step 3: Build both targets, verify each of the three on the simulator**

For each: tap → sheet opens prefilled with the resume occurrence → save → badge flips on that
occurrence's calendar cell.

- [ ] **Step 4: Commit**

```bash
git commit -am "fix(ios): list and detail Post now resume from the oldest unresolved occurrence"
```

---

### Task 10: The notification action posts the resume occurrence

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Notifications/NotificationService.swift:123`
- Test: extend `ios/FinchApp/Tests/FinchAppTests/NotificationPlannerTests.swift`

- [ ] **Step 1: Resolve the occurrence before posting**

This path has no UI and must stay silent. Replace `:123`:

```swift
                if let id = focusId, let store {
                    let t = store.scheduled.first { $0.id == id }
                    let posted = Selectors.scheduledPostedMap(store.txns)
                    let occ = t.flatMap { Selectors.resumeOccurrence(template: $0, posted: posted, today: store.wallToday) }
                    var args: [String: JSONValue] = ["templateId": .string(id)]
                    if let occ { args["date"] = .string(occ) }
                    try? store.apply(.postScheduled, Args(args))
                }
```

Omitting `date` when no occurrence resolves preserves today's behaviour exactly.

- [ ] **Step 2: Build both targets; run the full suites**

Run: `cd ios && swift test`, then the `FinchApp` scheme test action.
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git commit -am "fix(ios): notification Post action records the occurrence it refers to"
```

---

**End of PR 2.**

## Verification checklist (both PRs)

- [ ] `cd ios && swift test` — FinchCore + the four ParityTests gates
- [ ] `FinchApp` scheme test action — FinchAppTests
- [ ] `cd frontend && bun test lib && bun run typecheck && bun run lint`
- [ ] `FinchApp` (simulator) **and** `FinchMac` both build
- [ ] Simulator: the original repro — post a missed occurrence, badge flips `missed` → `done`
- [ ] Simulator: posting with a **changed** date still resolves the original occurrence
- [ ] A split-income template still posts one transaction per split account
