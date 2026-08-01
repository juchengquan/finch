# Date **and time** on every editable date — design

**Date:** 2026-08-01
**Status:** phases 1–3 implemented; phase 4 designed, not started
**Origin:** a device report — "in edit page, there is no way to edit the time. We
should always keep add/edit to be consistent"

## What prompted it

An audit of every date input in the app, add and edit alike:

| Screen | Add | Edit | Time? |
|---|---|---|---|
| Transaction | date + time | date + time | yes |
| Adjust balance | date + time | — | yes |
| **Scheduled item** | date, editable | **read-only text** | **no** |
| Budget (start/end) | date | date | no |
| Reconcile (as of) | date | — | no |
| Transaction filter (from/to) | date | — | no |

Two separate defects hid behind one symptom. Add/edit were consistent *everywhere
except Scheduled*, and the missing time is a different thing again: transactions
carry one, nothing else does.

**Decision:** every editable date gains a time. Taken deliberately, against the
argument that budget cycles and filter ranges are day-granular by nature — the
counter-argument being that every transaction already carries date AND time, so the
data supports it and the granularity mismatch is what surprises people.

## Storage: mirror `entries`, don't invent

`entries` already stores `date TEXT` and `time TEXT` as **separate, nullable**
columns. Every new time follows that: `start_time` beside `start_date`, and so on.

Why not a single datetime column:

- **Additive migrations.** Old rows keep working with a NULL time.
- **Nothing changes until a time is set.** Every existing `yyyy-MM-dd` string
  comparison in the engine keeps its meaning; a NULL time reads as "unspecified",
  not midnight.
- **It is the house pattern**, so the web port has an obvious shape too.

The cost is that a fully-specified moment is two columns, and any comparison that
must honour the time has to consider both. That is a real cost, and it is why the
phases below are ordered by how much comparison logic each one disturbs.

## Phase 1 — a schedule's Start becomes editable (IMPLEMENTED)

No schema change. The sheet showed Start read-only and said why:

> On edit, type / account / start date are not patchable (the engine omits them)

It was right: `startDate` was missing from `Scheduled.cols`, the patchable-column
map, so the value was silently dropped. Adding it makes the field editable.

**There is no `next_run` to recompute.** Occurrences are DERIVED —
`Forecast.occurrencesUpTo` anchors on `startDate ?? nextRun` — and `next_run` is
inserted NULL and never written by any action. So moving the start moves the whole
schedule for free.

Worth knowing for anyone reading the tests: the start is an **anchor, not an
occurrence**. A monthly schedule on day 1 whose start moves to 15 March produces its
next occurrence on **1 April**, not 15 March.

## Phase 2 — a scheduled item posts at a time you choose

`scheduled_templates` gains `start_time` (and `end_time` for symmetry).

**This is not "add a missing time".** Generated transactions already get one: the
silent posting path stamps **now**, and `AddTransactionSheet` deliberately matches
that when prefilling, with the reason recorded:

> stamping the occurrence at local midnight would otherwise sink it to the bottom of
> today's list

**Corrected while implementing.** That comment is wrong about the silent path: it
passes no time at all, and `Entries` inserts `e.time` with no default — so generated
transactions get NULL and **sink to the bottom of their day** (the feed orders by
`date DESC, time DESC`; SQLite sorts NULLs last). The sheet avoids that; the silent
path causes it.

Stamping the firing moment fixes it, was implemented, and **fails
`WriteParityTests`** — the web oracle writes NULL. So phase 2 ships the half that is
an iOS decision (use a time the user chose) and leaves the NULL case alone. Making
postings always carry a time is a **parity decision requiring the web to move too**,
and is deliberately out of scope here.

## Phase 3 — budget cycles carry a time (IMPLEMENTED, both stacks)

`budgets` gains `start_time`/`end_time`. This was the phase with teeth:
`Selectors.cycleWindow` is entirely `yyyy-MM-dd` string arithmetic, and its
boundaries (`while e <= now`) become datetime comparisons the moment a time exists.

**The rule, stated once:** a cycle runs from its start moment to the next start
moment, **exclusive at the top** — "resets at 09:30 on the 1st". With no time that is
midnight-to-midnight, which is exactly what every budget did before.

**How the old behaviour was kept byte-identical.** `cycleWindow` early-returns into
the untimed code the instant `startTime` is nil, so the timed comparison is code the
existing 364 tests never reach. Everything downstream (`usedInWindow`,
`budgetMatchedTransactions`) shares one `inWindow` helper rather than two
hand-matched copies of the boundary rule.

The web moved with it (the parity decision: the web follows iOS), so the fixture
sequence carries a second budget `b2` that differs from `b1` only by
`startTime: '09:30'` — the pin that proves the column survives the write path on both
stacks and lands in canonical state.

**"00:00" is not a time.** The picker always produces one, so a budget saved
without touching it stores midnight — and midnight IS the untimed behaviour. Both
engines normalise it back to the untimed branch when reading the window, rather
than at the write path, so no route into the database can bypass it. Without this
every budget saved from the sheet would take the timed branch, where `to` means the
next start day, and report a day it does not have: the "32 days left in a 31-day
month" report, reintroduced.

**What `to` means, and who had to be told.** In the timed branch `to` is the day the
cycle STOPS on, not its last day. Three readers assumed the older meaning and were
corrected: the History chart (its bars would disagree with the figure printed above
them), the detail page's selected-cycle transaction list, and the days-left
countdown on both stacks.

**Deliberately left date-granular:** `invalidateRollover`. It compares periods to
`last_rolled_period` to decide whether a cached rollover must be recomputed, and
being one cycle early there costs a recompute, not a wrong number. Its input is a
date with no time, so honouring the turnover would be guesswork dressed as
precision.

## Phase 4 — reconcile as-of, and the filter range

Both are read-only consumers rather than stored state, so they benefit from the
comparison helpers phases 2–3 introduce. Cheapest last.

## Parity — DECIDED: the web follows iOS

Taken 2026-08-01. Every phase from here changes **both** front-ends and regenerates
the fixtures; the two schemas do not diverge.

Phase 1 needed no such decision — it only stopped dropping a value the schema always
had.

What "the web follows" costs, per phase:

| | iOS | web | fixtures |
|---|---|---|---|
| 2 — chosen posting time | done (#681) | `start_time` column + `postScheduled` threading | regenerate |
| 2b — always stamp a time | one line, reverted for parity | thread a time through `postSingle`/`postTransfer` | regenerate |
| 3 — budgets carry a time | `cycleWindow` becomes datetime-aware | same, in `lib/select.ts` | regenerate; every boundary answer moves |
| 4 — reconcile + filter | UI only | UI only | none |

**Sequencing note.** 2b is the cheapest way to prove the whole "web follows"
workflow — one behaviour, both stacks, fixtures regenerated, both suites green —
before phase 3 does the same thing to every budget boundary in the fixture set. Do
it first.

`frontend/scripts/export-fixtures.ts` is the regeneration entry point, and
`ios/README.md` documents its two gotchas.
