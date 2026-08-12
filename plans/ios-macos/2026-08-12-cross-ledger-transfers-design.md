# Cross-ledger transfers — design

**Date:** 2026-08-12
**Status:** designed, not implemented
**Origin:** "based on our database design, do we allow transactions across ledger?" —
answered *no* (below), then grilled into a design for adding them.

> **This is the most expensive change proposed this cycle**, because it touches the
> two things that ARE the safety net: the byte-pinned schema and the audit. Read the
> Bill section before agreeing to build it.

## Where we start: today the answer is no, deliberately

`plans/database_design_en.md` §34: *"All data is scoped to a ledger. **Ledgers never
share data.**"* The schema backs it: `entries.ledger_id`, `accounts.ledger_id` and
`categories.ledger_id` are all `NOT NULL`, and **audit rule 6 (`cross-ledger`)** flags
any posting whose account or category sits in a different ledger than its entry —
i.e. today a cross-ledger posting is *corruption*, not a feature. Since import runs
the audit as a gate before swapping the live DB, a `.finch` pack containing one is
rejected outright.

Two caveats found while confirming this, both worth knowing independently of whether
this feature is built:

- **Nothing enforces it at write time.** There is no trigger for rule 6 (the schema
  has triggers for balance, posting currency, sealed-entry edits and holdings — not
  this). `Entries.postTransfer` derives the entry's ledger from the **from-account
  only** and never even reads the to-account's `ledger_id`. A caller passing two
  accounts from different ledgers would silently write exactly the corruption rule 6
  flags. What prevents it today is the app layer: `FinchStore` projects only the
  active ledger, so the pickers cannot offer a foreign account.
- **The one deliberate exception to ledger isolation** is `counterparties`
  (merchants), global since 2026-07-20 — no `ledger_id`, one catalog for every ledger.

## The design in one picture

```
PERSONAL (base USD)                    TRAVEL (base EUR)
  Checking            −$5,000.00         Travel Card         +€4,600.00
  ← moved out of books +$5,000.00        → moved in          −€4,600.00
                      ──────────                             ──────────
                           $0.00 ✓                                €0.00 ✓
  kind = interledger                     kind = interledger
  link_id = xfer_ab12 ─────────────────  link_id = xfer_ab12
  description "Travel · Travel Card"     description "Personal · Checking"
```

Personal's net worth **drops** by $5,000. Travel's rises by €4,600. Each entry is
complete and true on its own; the link exists so the UI can treat them as one thing.

---

## Decisions

### D1 — Two linked entries, never one entry spanning two ledgers

**Decided:** a pair, one entry per ledger.

**The single-entry design is structurally dead, not merely awkward.** `entries.ledger_id`
is one `NOT NULL` column, so an entry cannot belong to two ledgers. More fundamentally
the seal trigger enforces `ROUND(SUM(amount_base), 2) = 0` per entry — and `amount_base`
means *that ledger's* base currency. Personal (USD) and Travel (EUR) have different
bases, so "sums to zero in the base" is not even a well-formed statement across them.
Any variant of this idea also has to defeat audit rule 6, which exists to catch it.

Precedent for one user-facing thing spanning several entries already exists:
`entries.group_id` links the entries of one grid purchase (TEXT, no FK, iOS-only,
deliberately outside the parity snapshot).

### D2 — The balancing leg is a new equity system category; the source book gets poorer

**Decided:** a fourth system category, `system = 'interledger'`, beside
`opening` / `adjustment` / `fx`.

Every entry needs a second leg that cancels the account leg — the seal trigger refuses
to save one that doesn't. What that leg points at is a **semantic** choice, not
plumbing, because it decides what the source book's total says afterwards:

| Balancing leg | Personal's total after moving $5,000 |
|---|---|
| equity category ("moved out of these books") | **−$5,000** — the money left |
| clearing account ("Travel owes me") | unchanged — cash became a receivable |

The equity category matches what a person means by "I moved it to my travel budget".
The clearing-account version is impeccable inter-company bookkeeping and the wrong
mental model here: finch's ledgers are organizational containers for one person's
money, not entities that lend to each other. It would also leave a pseudo-account that
accumulates forever and never settles. (`accounts.type` does already include
`virtual` — "virtual account used for splitting income" — but repurposing it would
muddy an existing meaning for no gain.)

**Why a *system* category rather than an ordinary hidden one.** `kind = 'equity'`
alone already buys the behavior — such rows are hidden from pickers and excluded from
spend aggregations. But a `system = NULL` category can only be resolved by name or id,
which the decision record explicitly forbids for system rows (*"resolved by this
column (rename-safe), never by id or name"*). A user rename or delete would quietly
break every future transfer. `idx_cat_system` also already enforces one row per
`(ledger_id, system)` for free.

**Cost:** `categories.system` is `CHECK(system IN ('opening','adjustment','fx'))`.
SQLite cannot alter a CHECK in place, so this is a table rebuild. See the Bill.

### D3 — A new entry kind, and the audit learns its shape

**Decided:** `entries.kind = 'interledger'`, plus a sixth `kind-shape` clause.

`entries.kind` has **no** CHECK constraint, so a new value costs no DDL. But invariant
I7 (`kind-shape`) enumerates a contract per kind, and our shape — one account leg plus
one equity leg — fails both plausible existing labels:

| Reusing | Contract | Our shape |
|---|---|---|
| `transfer` | exactly 2 account legs | has 1 → **fails** |
| `expense` / `income` | ≥1 account leg **and ≥1 ordinary (non-equity) category leg** | has 0 ordinary → **fails** |

Either reuse would fail the audit on *every* cross-ledger transfer — and because import
gates on the audit, the user's own backups would stop importing.

A new kind slips through untouched (the rule only flags kinds it recognizes), which is
precisely why the clause must be **added deliberately** rather than relied on to pass:

```
+ interledger   acct == 1, plain == 0, eq_inter == 1
```

Without it these entries would have no shape contract at all — the seal trigger would
still force them to balance and hold an account leg, but nothing would catch a bug
writing two account legs or pointing the equity leg at the wrong label.

Useful side effect: the projection pairs transfer legs with
`kind == "transfer" && acctCount >= 2`, so `interledger` rows are never mistaken for
one half of an ordinary transfer.

### D4 — One transfer: edited and deleted as one

**Decided:** a shared link id on both entries; tapping either side opens one editor
showing both amounts; saving writes both books; deleting removes both.

This mirrors today's cross-currency transfer sheet, which already presents a *From*
field and a *To* field side by side — so "edited as one" does not mean deriving one
amount from the other.

**A new nullable TEXT column, not `group_id`.** Overloading `group_id` (already "one
purchase split across cards") would make any query for grid siblings find the
cross-ledger partner. The marginal cost of the column is ~zero: it rides the migration
D2 already forces.

**Consequence:** a write started in Personal now touches Travel's rows, so the app must
refresh a ledger the user isn't looking at. This is the second place (after D6) where
the one-ledger-at-a-time model is deliberately breached.

### D5 — The arriving amount prefills from the stored rate, and stays editable

**Decided:** type $5,000, finch suggests €4,600 from its FX table, you overwrite it
with what the bank actually gave you. `Entries.postTransfer` already takes an optional
received amount and converts when absent, so this is the existing behavior.

**Accepted, knowingly:** unlike a same-ledger cross-currency transfer — which posts an
FX-residue equity leg to keep one book honest — **nothing here can detect a wrong
rate**. Each book balances alone, so any pair of numbers is accepted; a typo loses or
invents money in a hypothetical all-ledgers view. This is inherent to separate books,
not a gap that can be closed, and it is the one genuinely unguarded surface in the
design.

### D6 — Started from the Transfer type's To picker

**Decided:** keep four transaction types; the To picker grows an "Other books" section
below the active ledger's accounts.

It *is* a transfer, so it lives where transfers live and inherits the sheet, the amount
fields and the FX behavior. **Cost:** that picker becomes the first place the app
deliberately reads accounts outside the active ledger.

No conversion edge case exists: the edit sheet's transfer legs are read-only
(`updateTransfer` treats accounts as immutable), so an ordinary transfer can never be
mutated into a cross-ledger one.

### D7 — The destination name is stored at write time

**Decided:** stamp the row's description with `"Travel · Travel Card"` when it's
written.

The row reads correctly forever with zero cross-ledger work at render time. Resolving
it live would mean the projection reaching into another ledger every time it builds
Personal's list — the first crack in the one-ledger projection model, on the hot path.
**Accepted cost:** rename that account in Travel next year and Personal's old rows show
the old name. Stale, never wrong about the money.

### D8 — Deleting a ledger leaves the surviving half valid, and generic

**Decided:** allow the delete; the orphan survives and degrades its wording.

`entries.ledger_id` is `ON DELETE CASCADE`, so deleting Travel removes Travel's half.
Personal's half is self-contained — Checking −$5,000 against "moved out of these
books" — so it still balances, Personal's history stays true, no balance changes and no
audit code fires. It simply loses its pointer and reads generically from then on.

**Rejected — cascade to both halves:** deleting Personal's half would erase a genuine
$5,000 movement out of Checking, retroactively changing Personal's balance and every
running balance after it. *Deleting one book must never rewrite another book's history.*

**Rejected — block the delete:** the only way to clear the blocking transfers would be
deleting real money movements, which has the same problem, and it makes discarding a
scratch ledger surprisingly hard.

---

## The bill

**Schema (both front-ends, byte-for-byte, `SCHEMA_VERSION` bump):**

1. `categories.system` CHECK gains `'interledger'` → **table rebuild** (SQLite cannot
   alter a CHECK). Precedented: `2026-07-23-counterparties-global` did exactly this
   pattern — build new table, copy, drop, `RENAME TO`.
2. `entries` gains a nullable TEXT link column → plain `ALTER TABLE ADD COLUMN`,
   precedented many times over.

**No data backfill.** `ensureSystemCategories` creates system rows **lazily** on first
use, so existing ledgers grow their `interledger` category the first time one is
needed. The migration is pure DDL.

**Engine, mirrored on the web** (verbatim ports under parity gates):

- the sixth `kind-shape` clause in `Audit.swift` (guarded by `AuditParityTests`);
- `ensureSystemCategories` gains its fourth row;
- parity fixtures regenerate.

**Native-only, not mirrored:** the write action and every pixel of UI — precedent:
`setEntryAttachment`, `setBudgetOrder`, `setTrackedCurrencies` are native-only actions
the web ignores. The web keeps its oracle job: it can read, audit and round-trip a
database containing cross-ledger transfers; it can never create one. Consistent with
the 2026-08-08 freeze — `lib/db` is the maintained surface, `app/` is not.

## Out of scope for v1

- **Recurring cross-ledger transfers.** `scheduled_templates.kind` is separately
  constrained to `('income','expense','transfer')`, so a standing "$500 to Travel every
  month" needs a **second** table rebuild plus its own poster and audit expectations.
  Nothing in this design blocks adding it later; wait until real use says you want it.
- **An all-ledgers combined view.** Out of scope and unrelated, but note it is the only
  place a mistyped FX rate (D5) would ever be visible.

## What comes for free

| Surface | Why nothing is needed |
|---|---|
| Reconcile mode | the account leg is an ordinary leg — it ticks, clears and seals like any other |
| Budgets / Insights | `kind='equity'` categories are already excluded from spend aggregations |
| Audit rule 6 (`cross-ledger`) | still passes untouched: every posting stays inside its own entry's ledger |
| Projection's transfer pairing | requires `kind == "transfer"` **and** ≥2 account legs — `interledger` rows can't be mistaken for one |

## Verification

Nothing here is covered by the existing parity gates for the write path (the action is
native-only), so tests carry the full weight:

- **Pure logic** — the pair builder: both entries balance in their own base; the equity
  leg resolves by `system` marker, not name; the link id is identical; descriptions are
  stamped from the partner.
- **Audit** — the new clause CATCHES the malformed shapes it exists for (two account
  legs; missing equity leg; equity leg pointing at `adjustment` instead), and passes a
  well-formed pair. Run against a fixture DB containing one.
- **Migration** — a DB created before the change opens, migrates, and accepts an
  `interledger` category afterwards; an existing ledger with no such category still
  works and grows one lazily on first transfer.
- **Round-trip** — export a DB containing a cross-ledger pair and re-import it: the
  audit gate must accept it (this is the test that proves the audit clause and the
  writer agree).
- **UI** — create from the To picker's "Other books" section; edit updates both halves;
  delete removes both; delete the destination LEDGER and the survivor still balances,
  reads generically, and leaves Personal's balance unchanged.
- **Currency** — figures render in each account's own currency, on an account whose
  currency differs from both its ledger base and the display currency.

## Open question

**Does an interledger row belong in the destination ledger's "income" figures?** The
equity leg keeps it out of spend/income aggregations by construction, which is almost
certainly right — €4,600 arriving from your own other book is not income. Worth a
second look on real data before shipping, because Insights is where it would surprise
someone.
