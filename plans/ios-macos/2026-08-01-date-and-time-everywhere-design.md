# Date **and time** on every editable date — design

**Date:** 2026-08-01
**Status:** phase 1 implemented; phases 2–4 designed, not started
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

So the feature is *choosing* that time instead of it being whenever the app fired.
`start_time` becomes the intended time-of-day; the posting path uses it when set and
falls back to now when NULL.

## Phase 3 — budget cycles carry a time

`budgets` gains `start_time`/`end_time`. This is the phase with teeth:
`Selectors.cycleWindow` is entirely `yyyy-MM-dd` string arithmetic, and its
boundaries (`while e <= now`) become datetime comparisons the moment a time exists.
Parity fixtures pin the current answers.

Do this one alone, and decide the web's position explicitly before starting.

## Phase 4 — reconcile as-of, and the filter range

Both are read-only consumers rather than stored state, so they benefit from the
comparison helpers phases 2–3 introduce. Cheapest last.

## Parity

Every phase touches `plans/database_design_en.md`, the model the web shares. Each
carries the same decision: the web follows, or the two schemas diverge deliberately.
Phase 1 needs no such decision — it only stops dropping a value the schema always
had.
