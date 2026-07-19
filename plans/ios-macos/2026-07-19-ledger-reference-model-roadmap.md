# Ledger reference-data model — roadmap (Categories/Tags copy · Merchants global)

**Date:** 2026-07-19
**Status:** Design approved in a grill-me exploration; two phase specs follow (linked below).
**Origin:** "When I switch ledgers, everything under Settings › Ledger changes. Should
these be universal instead of per-ledger?"

## The finding

Every reference table is scoped by `ledger_id NOT NULL REFERENCES ledgers(id) ON DELETE
CASCADE` — **except FX**. So a ledger is a fully self-contained book (its own chart of
accounts, categories, tags, merchants, budgets, transactions), and the engine *enforces*
isolation: the audit raises a `cross-ledger` corruption if a transaction references another
ledger's account or category (`Audit.swift`). This schema is **byte-shared with the web**
and version-locked (`Schema.version` == web `SCHEMA_VERSION`, asserted in 3 test suites;
parity fixtures cover these tables).

**Not all four domains want the same treatment** (decided in discussion):

| Domain | Nature | Decision |
|---|---|---|
| **Categories** | a per-book *taxonomy choice* (business ≠ personal) | **stay per-ledger** + copy affordances |
| **Tags** | same — a per-book labeling choice | **stay per-ledger** + copy affordances |
| **Merchants** | a *real-world entity* ("Starbucks" is the same everywhere) | **go global** (schema change) |
| **Currencies (FX)** | *universal facts* (a USD→EUR rate isn't ledger-specific) | **already global** — little/no work |

Key correction from the schema: **`exchange_rates` has no `ledger_id`** (PK `(date,
currency)`), and the tracked-fetch list is a single global `app_state.fxTrackedCurrencies`
key. So FX is already global; only each ledger's *base currency* differs (inherent).

## Why "universal for everything" was rejected

Some ledgers are genuinely separate books (different base currency, business vs personal),
so globalizing *categories* would corrupt those — and the cross-ledger audit would fight it.
The real pain (re-creating the same catalogs across ledgers) is better solved by **copy/clone
within the per-ledger model** (categories/tags) and by **globalizing only what is truly a
shared entity** (merchants).

## The unlock: nothing has shipped yet

No live databases ⇒ **no data migration.** A schema change becomes "edit the baseline DDL +
stamp a fresh version (v0.1)". Pre-launch is the cheapest time to change the schema (post-launch
is ~100× harder), so the merchants-global change is a *smart-now* move, not a risky one. Parity
is kept by moving the **web schema + `lib/db` in lockstep** (the web UI can lag); fixtures are
re-derived; version bumped to a fresh baseline.

## Phases

- **Phase 1 — Categories & Tags copy** (no schema change, iOS-native-first): ship now.
  → `2026-07-19-ledger-reference-copy-phase1-design.md`
- **Phase 2 — Merchants global** (schema baseline change to v0.1, parity-coordinated;
  currencies re-scoped to near-zero): its own careful spec.
  → `2026-07-19-global-merchants-phase2-design.md`

The phases are independent (Phase 1 touches per-ledger categories/tags; Phase 2 touches the
merchants schema) — either can land first. Recommended: Phase 1 as a quick win; Phase 2 while
pre-launch keeps the schema change cheap.
