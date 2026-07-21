# Posting a scheduled occurrence — design

**Status:** design, approved 2026-07-21. Implementation plan to follow.
**Reported as:** "when we press the missed item in Scheduled and select 'Post now', the
status of 'missed' does not change. same the upcoming items."

## 1. The bug

On the Scheduled calendar, selecting a day and choosing **Post now** on an occurrence
leaves its badge unchanged — `missed` stays `missed`, `upcoming` stays `upcoming` —
even though a transaction *was* created.

Reproduced on the simulator with `wallToday = 2026-07-21`: posting the `Gym Membership`
occurrence dated `2026-07-15` leaves the Jul 15 cell reading `missed`.

## 2. Root cause

The occurrence date is discarded **twice**.

**At the view.** `ScheduledCalendarView` knows exactly which occurrence was pressed, but
its callback drops it:

```swift
var onPost: (ScheduledTemplate) -> Void          // no date
… if st == .upcoming || st == .missed { Button { onPost(t) } … }
```

**At the action.** `postScheduled` accepts only a template id and stamps the wall clock
(`Scheduled.post`, `Store/Domain/Scheduled.swift:40`):

```swift
struct A: Decodable { let templateId: String }
…
let date = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
```

So posting the Jul 15 occurrence writes a transaction dated **Jul 21**. The badge is
resolved by `Selectors.scheduledPostedMap`, which keys on the *transaction's* date:

```swift
for t in txns { if let s = t.sourceTemplateId { out["\(s)|\(t.date)"] = (t.pending ?? false) } }
```

The Jul 15 cell looks up `"gym|2026-07-15"`, finds nothing, and stays `missed`. The
transaction lands on the Jul 21 cell, which is not an occurrence, so nothing appears
resolved anywhere. Upcoming behaves identically.

**The automatic path already does this correctly.** `Scheduled.generateDue` posts each
occurrence *at its own date* (`for date in dates`, from `occurrencesUpTo`) and dedupes
against dates already posted. The badge semantics were designed around that convention;
manual `postScheduled` is the outlier.

**Aggravating factor:** `generateDueScheduled` is **never invoked by the app**. The
catch-up path exists in the engine but nothing calls it, so missed occurrences accumulate
indefinitely and **Post now is the only way to resolve one**. That makes this bug a dead
end, not a cosmetic glitch.

## 3. Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Post now opens the edit sheet**, prefilled from the template and occurrence | Sidesteps guessing the date; also lets the user correct amount/category before it lands in the ledger |
| 2 | Resolution tracked by an **explicit `occurrence_date` link**, not by the transaction's date | The badge is then correct even when the user changes the date in the sheet |
| 3 | **All four UI entry points** open the sheet; the notification action stays silent | Consistency; the notification has no UI to present |
| 4 | **Split-income templates keep the silent path** | The sheet structurally cannot express N accounts (§6) |
| 5 | Non-calendar entry points use **resume semantics** — oldest unresolved first, then next upcoming | Matches `generateDue`'s catch-up order; lets a backlog be cleared from the list |
| 6 | The **web changes in the same PR** | Monorepo; if the web posts without the link, native shows the occurrence as still missed |

### Rejected alternatives

- **Prefill the date and keep keying on it (no schema change).** One PR, no migration. Rejected:
  the badge is only right if the user leaves the date alone — changing it to "the day I actually
  paid" strands the occurrence as `missed` forever.
- **Teach the sheet account-splits.** Fully consistent, but a substantial new editor surface for a
  concept the sheet has never had — larger than the rest of this work combined.
- **Let split templates collapse to one transaction.** Silently discards user-configured splits.
- **Lock the date in the sheet.** Guarantees resolution with no schema change, but blocks the
  honest "due the 15th, paid today" case.
- **Wire up `generateDueScheduled` for automatic catch-up.** Would fix the backlog problem at its
  root, but auto-creating transactions the user never confirmed is a behaviour change well beyond
  this bug. Noted as follow-up (§9).

## 4. Schema

One additive, nullable column beside the existing `source_template_id`:

```sql
ALTER TABLE entries ADD COLUMN occurrence_date TEXT;   -- yyyy-MM-dd, NULL for non-scheduled
```

`SCHEMA_VERSION` bumps to the **next unused timestamp** — `2026-07-21T00:00:00Z` is already
taken by the budget-match columns, so use `2026-07-22T00:00:00Z`.

Changes, mirroring the `2026-07-21-budget-match-columns` precedent exactly:

- `frontend/lib/db/core/schema.ts` — column in `SCHEMA`, `SCHEMA_VERSION` bump, `MIGRATIONS` entry
- `ios/…/Storage/Schema.swift` — re-emitted byte-for-byte, `Schema.version` bumped
- `ios/…/Storage/Migrations.swift` — new duplicate-tolerant migration:

```swift
migrator.registerMigration("2026-07-22-entry-occurrence-date") { db in
    do { try db.execute(sql: "ALTER TABLE entries ADD COLUMN occurrence_date TEXT") }
    catch { if !"\(error)".contains("duplicate column") { throw error } }
    try Self.ensureMetadataRow(db)
}
```

- `ios/…/Tests/FinchCoreTests/SchemaTests.swift` — the hardcoded version literal (a deliberate tripwire)

**Existing data keeps working.** The resolution rule falls back to the transaction date when
`occurrence_date` is NULL (§5), which is exactly today's behaviour — so every historical
`generateDue` posting still resolves, with no backfill.

**Blast radius is contained.** `Pack`, `DownSync` and the CloudKit mappers do not enumerate entry
columns, so the new one rides along without changes.

## 5. Resolution rule

`Selectors.scheduledPostedMap` keys on the occurrence link when present, else the transaction date:

```swift
out["\(s)|\(t.occurrenceDate ?? t.date)"] = (t.pending ?? false)
```

`Tx` gains `occurrenceDate: String?` (`Project/Models.swift`), read in `Projection.run()`
alongside the existing `sourceTemplateId` (`Project/Projection.swift:84`).

Badge states are unchanged: absent ⇒ `upcoming` if the date is still ahead, else `missed`
(shipped in #568); `true` ⇒ pending; `false` ⇒ done.

## 6. Behaviour by template kind

The sheet cannot represent every template, so the flow branches:

| template kind | flow | note |
|---|---|---|
| simple (fixed amount) | **sheet** | the common case |
| variable amount | **sheet** | *fixes* today's `error.scheduled.variableAmount` — "add it manually" is precisely what the sheet is |
| transfer | **sheet** | `addTransfer` already accepts `sourceTemplateId` |
| installment | **sheet**, cap re-checked on save | the cap lives in `post()`; the sheet path must not bypass it |
| **split income** | **silent `postScheduled`**, with the date fix | `scheduled_splits` fan out across *accounts*; the sheet's splits are *categories* within one transaction — a different concept |

Split templates are detected by a non-empty `scheduled_splits` for the template.

## 7. Entry points

| # | entry point | occurrence | behaviour |
|---|---|---|---|
| 1 | Calendar occurrence context menu | the pressed one | opens sheet |
| 2 | List row swipe "Post" | resume (§3.5) | opens sheet |
| 3 | List row context menu "Post now" | resume | opens sheet |
| 4 | `ScheduledDetailView` "Post now" | resume | opens sheet |
| 5 | `NotificationService` action | resume | **silent** — no UI available |

Entry point 2 becomes modal, which is unusual for a swipe action; accepted deliberately for
consistency.

**Resume semantics:** the earliest occurrence with no posting for it; if none is unresolved, the
next occurrence at or after `wallToday`. Repeated taps clear a backlog oldest-first.

## 8. Action surface

Two shared actions gain **optional** arguments — absent ⇒ today's behaviour, so web parity and the
`WRITE_SEQUENCE` gate are undisturbed (`postScheduled` is already excluded from `WRITE_SEQUENCE`
because it stamps wall-clock "today"):

```
postScheduled:  { templateId, date?, occurrenceDate? }
addTransaction: { …existing…, sourceTemplateId?, occurrenceDate? }
addTransfer:    { …existing (already has sourceTemplateId)…, occurrenceDate? }
```

`addTransaction` currently **cannot** set `sourceTemplateId` at all, while `addTransfer` already
can (`Store/Domain/Transfers.swift:62`) — this closes that asymmetry. Without it, a transaction
saved from the sheet carries no link to the template and the badge would still never flip: the
bug would look fixed and behave identically.

`generateDue` also stamps `occurrence_date = date`, so both posting paths agree.

## 9. Testing

- **Engine (`FinchCoreTests`)** — `postScheduled` with an explicit `date`/`occurrenceDate` writes
  both columns; without them, behaviour is byte-identical to today (parity guard). `generateDue`
  stamps `occurrence_date`. Installment cap still throws when the plan is complete.
- **Selector** — `scheduledPostedMap` prefers `occurrenceDate`, falls back to `date` when NULL
  (the no-backfill guarantee). A transaction dated Jul 21 with `occurrenceDate` Jul 15 resolves
  the **Jul 15** cell and not the Jul 21 one.
- **Resume order** — with Jul 8 and Jul 15 unresolved and Jul 25 next, three successive posts
  resolve Jul 8, Jul 15, Jul 25 in that order.
- **App (`FinchAppTests`)** — split-income templates route to the silent path; the other four
  kinds route to the sheet.
- **Migration (`MigrationsTests`)** — an existing DB gains the column; running twice is idempotent
  (duplicate-column tolerance).
- **Simulator** — the reported repro: post the Jul 15 occurrence, badge flips `missed` → `done`.
  Measure with `idb ui describe-all`, not screenshots.

### Bonus: this unlocks parity coverage

`postScheduled` is currently excluded from `WRITE_SEQUENCE` with an explicit reason —
*"it stamps `new Date()`, so it can't be reproduced offline"*
(`frontend/scripts/export-fixtures.ts:493`). Once it accepts an explicit `date`, that reason
disappears: a pinned-date call **is** reproducible, so `postScheduled` can finally join
`WRITE_SEQUENCE` and get a write-parity gate it has never had. Worth doing in this work while the
context is loaded — it closes a known hole rather than leaving the highest-risk scheduled action
unverified against the web.

(`createAccount`-with-`openingBalance` is excluded for the same reason and would need the same
treatment — an opening-date arg. Out of scope here, but the pattern is identical.)

## 10. Out of scope

- **Wiring up `generateDueScheduled`.** It is dead code today, which is why backlogs accumulate.
  Fixing that means auto-creating unconfirmed transactions — its own design conversation.
- **Backfilling `occurrence_date` for historical postings.** Unnecessary: the NULL fallback
  preserves today's behaviour exactly.
- **`Scheduled.post`'s use of `ISO8601DateFormatter()` for "today"** (UTC, so a day behind before
  08:00 at UTC+8 — the engine-side sibling of #570). Real, but it is FinchCore, where the fix must
  be taken with web parity in mind. Filed separately.
