# Multi-currency accounts — scoping / design plan

Status: **Phases 1–3 done + Phase 4 partial** (storage correctness + read/native
display + entry UX + cross-currency transfer UX; unrealized-FX and base-change tool
deferred with rationale). Builds on `FX_CONVERSION_PLAN.md` (entry→base conversion,
done) and the domain model in `database_design_en.md` (§"Multi-currency",
`transactions.amount_base`).

- ✅ **Phase 1** — `amount_base` is now the **ledger base** at every writer
  (`addTransaction`, `insertTxRow` for transfers/recurring, scheduled auto-post);
  account balances accumulate the **account-currency delta** (`acctDelta` in
  `addTransaction`, mirrored in `recomputeAccount`): native amount when the entry
  is in the account currency, else the ledger-base figure for a foreign entry on a
  base-currency account (`t-jpy-1`). `ledgerBaseCurrency` helper added to
  `rates.ts`. No schema change; a no-op on all existing (account == base) data —
  full suite green, plus two new divergent-account tests in `mutations.test.ts`.
- ✅ **Phase 2** — read path + native display. `useMoney` gained `toBase` /
  `fmtFrom` / `shortFrom` (any-currency → base / display). `balanceSeries` walks
  the **native** amount (account currency) so a single account's curve ends at its
  native balance. `netWorthSeries` / `netWorthByMonth` take an optional `ToBase`
  (identity default) so mixed-currency balances sum in the ledger base — wired from
  `useMoney().toBase` on Insights. The accounts list keeps aggregates valid by
  re-expressing each balance in the ledger base (`balanceOf` → `toBase`), so group
  subtotals / net worth / `fmt` all stay correct in the display currency. The
  account **detail** card shows the native balance with an "≈ {display}" secondary
  (hidden when account currency == display). All no-ops when account == base; new
  selector tests in `select.test.ts`.
- ✅ **Phase 3** — entry UX + the deferred edit path. The add-expense form's
  currency now **follows the selected account** (read-only display, no free picker)
  so the native entry is always in the account's currency (decision 3); foreign
  spend is modelled via a dedicated `fx` account. `updateTransaction`'s amount edit
  re-derives `amount_base` from the account currency → ledger base (locking the rate
  on the row) instead of assuming `amount_base = amount`. No-ops when account ==
  base; new divergent-account edit test in `mutations.test.ts`.

## 0. Confirmed decisions

These three product forks were decided up front and shape everything below:

1. **Net worth valuation** — **spot headline + locked history.** The current
   net-worth *total* converts each account's native balance at today's rate (so a
   foreign balance reflects real value and moves with FX); the historical
   net-worth *chart* stays in locked ledger-base amounts (no drift on no-activity
   months).
2. **Balance display** — **native + "≈ display".** Account balances render in the
   account's own currency with a smaller secondary "≈ {display}" line.
3. **Entry currency == account currency (constrained).** A transaction is always
   entered in its account's currency; foreign spending is modeled via a dedicated
   foreign-currency (`fx`) account, not a foreign entry on a home-currency account.

Decision 3 is the big simplifier: there is **no separate "account-currency"
amount** to store, because the native entered amount *is* the account-currency
amount. The model stays at the original two figures — `amount` (native = account
currency) and `amount_base` (ledger base) — and **no new transaction column /
schema migration is required.** The work is correcting *what `amount_base`
converts to* and *which figure balances accumulate*.

## 1. Goal & intent

Treat an **account's currency** (what the account holds) as distinct from the
**ledger's base currency** (what stats are expressed in):

- An account's balance is denominated and shown in **its own** currency (a JPY
  savings account reads ¥, a USD card reads $), matching the existing `fx`
  ("Foreign currency account") account type.
- All **cross-account** reporting in a ledger — net worth, budgets, category
  spend, cash flow — is computed in the **ledger base currency**, then converted
  to the user's chosen **display currency** by `useMoney()` (unchanged).

Phase 0 (done): per-account `currency` is now a stored, editable, displayed
property (create form, edit dialog, detail panel). This plan covers making the
**money math** correct once an account's currency differs from its ledger's base.

## 2. The invariant that's quietly holding everything together

Today every account's `currency` **equals its ledger's `base_currency`**:

- Seed sets each account's currency to `baseOf(ledgerId)` (`lib/db/seed.ts`).
- The create form previously hard-coded `currency: active.base` (only just made
  user-selectable in Phase 0).

Because of that, the codebase conflates "account currency" and "ledger base"
without consequence. Phase 0 lets a user pick a divergent currency, which
**breaks** that conflation.

### 2.1 `amount_base` is computed in *account* currency, not ledger base

`addTransaction` (`lib/db/queries/transactions.ts:129-156`) does:

```
const baseCurrency = String(acct[0]?.currency ?? 'USD');   // ← ACCOUNT currency
const currency     = input.currency ?? baseCurrency;       // entry currency
const conv         = await convertToBase(exec, input.amount, currency, baseCurrency, input.date);
const amountBase   = conv.amountBase;                       // entry → ACCOUNT currency
const balanceAfter = currentBalance + amountBase;           // account currency
```

So the stored `transactions.amount_base` is in the **account's** currency — but
`database_design_en.md:480` defines it as *"`amount` converted to the ledger's
base currency … use this for all cross-currency aggregations."* The column's name
and the writer disagree; they only coincide today because account == base.

`current_balance` / `balance_after` / `opening_balance` then accumulate
`amount_base` (`recomputeAccount`, `lib/db/queries/accounts.ts:12-25`).

### 2.2 Every ledger-level stat sums account-currency figures as if comparable

`rowToTx` (`lib/db/queries/transactions.ts:43`) maps `Tx.amount = amount_base`.
The reporting selectors sum `Tx.amount` (or split `amountBase`) across **all
accounts in a ledger**:

- `netWorthSeries` / `netWorthByMonth` (`lib/select.ts:361`, `:138`) sum
  `account.balance` across accounts of different currencies.
- `categorySpend` (`lib/select.ts:45`), `monthlySpending` (`:96`),
  `monthlyCashflow` (`:284`), `incomeCategoryFlow` (`:255`) sum `Tx.amount` /
  split `amountBase`.

With one JPY account and one USD account in the same ledger, these add ¥ to $.

### 2.3 The display conversion is then wrong too

`useMoney()` (`components/use-money.ts`) converts `active.base → display`, assuming
its input is ledger base. When the figure is a mix of account currencies, the
conversion is meaningless.

**Net:** as soon as one account's currency ≠ its ledger base, **net worth, every
budget/spend/cash-flow stat, and the display conversion all silently corrupt**.

## 3. The model (under decision 3)

Two locked figures per transaction — **both already exist** in schema and store:

| Field (DB → store) | Currency | Role | Today | Fix |
| --- | --- | --- | --- | --- |
| `amount` → `Tx.nativeAmount` | account currency (== entry) | drives the account's **balance** + single-account series | native entered amount | **start using it** for balances |
| `amount_base` → `Tx.amount` | **ledger base** | drives all **cross-account** stats + display conversion | computed in *account* currency (bug) | **convert to ledger base** at write |

Because entry == account currency (decision 3), the native `amount` *is* the
account-currency amount — so balances accumulate **`amount`** (native), and
`amount_base` becomes a single conversion **account/entry currency → ledger
base**, locked with its rate. No third column.

## 4. Net worth valuation (decision 1, mechanics)

- **Flows** (category spend, cash flow, income) → locked `amount_base` (ledger
  base). Unchanged once the writer is fixed.
- **Historical net-worth series** (`netWorthSeries`, `netWorthByMonth`) → locked
  ledger-base `amount_base`, same as today's walk but now genuinely base.
- **Current net-worth headline** → **spot**: convert each account's native
  `current_balance` (account currency) → ledger base (or straight to display) at
  **today's** rate via `convertViaRates` (`lib/fx.ts`), then sum. Label it
  "at today's rates".

## 5. Schema & migration

- **No new transaction column.** `transactions` keeps `amount` (native) +
  `amount_base` (now genuinely ledger base) + `exchange_rate`/`exchange_rate_date`.
- **No structural migration**, but a **one-time recompute/backfill** is prudent so
  any rows already written under a divergent currency are corrected:
  - `amount_base := convert(amount, account.currency → ledger.base_currency, date)`
    (no-op for all existing rows, since account == base today).
  - Re-run `recomputeAccount` for every account so `current_balance` /
    `balance_after` / `opening_balance` derive from **native `amount`** (no-op
    today; correct under divergence).
- `transaction_splits.amount_base` must be **ledger base** (feeds `categorySpend`);
  the native split `amount` stays in account currency. Verify the sum-to-parent
  invariant is checked in base.
- `transfer_groups` already carries `from_currency`/`to_currency`/`amount_base`/
  `exchange_rate` — each leg is entered in its own account's currency (consistent
  with decision 3); confirm both legs' balances use native and the shared base
  figure is ledger base.
- Bump the export/import schema version (#46 added `db_metadata` + checksum) only
  if any column meaning changes are persisted in metadata; otherwise unaffected.

## 6. Write-path changes

Each writer fetches the **ledger's `base_currency`** (via the account's
`ledger_id`) in addition to the account currency it already reads, then:
`amount_base = convertToBase(native, account.currency, ledger.base, date)` and
**accumulates `native` (account currency) into the balance**, not `amount_base`.

- `addTransaction` (`lib/db/queries/transactions.ts:129`) — convert to **ledger
  base** for `amount_base`; `balance_after = currentBalance + native`.
- `recomputeAccount` (`lib/db/queries/accounts.ts:12-25`) — accumulate `amount`
  (native), not `amount_base`.
- `insertTransactions` + `seedOpeningByAccount` (`lib/db/seed.ts`) — derive
  opening from `Σ native`, base from ledger-base conversion.
- `createTransfer` (`lib/db/mutations.ts:218-227`) — per-leg native into each
  account's balance; ledger-base figure for reporting.
- Scheduled auto-post (`lib/db/mutations.ts:164`); reconcile / `adjustAccountBalance`
  (the adjustment is native account currency) — set native, convert to base.

## 7. Read-path / derivation changes

- `rowToTx` (`lib/db/queries/transactions.ts:43`): no shape change — `Tx.amount`
  (= `amount_base`) is now genuinely ledger base; `Tx.nativeAmount` (= DB `amount`)
  is the account-currency figure. The cross-account selectors become correct with
  **no change to them**.
- `balanceSeries` (`lib/select.ts:356`): reconstruct a single account's curve from
  **`nativeAmount`** (ends at the native `current_balance`) instead of `Tx.amount`.
- `netWorthByMonth` / `netWorthSeries` (`lib/select.ts:138`, `:361`): keep the
  locked-base walk for the **series**; compute the **headline** via spot
  revaluation of native balances (§4).
- `useMoney()` unchanged — now correct, inputs are truly ledger base.
- **Account-native display path**: `fmtNative(balance, account.currency)` for the
  primary balance, plus a secondary "≈ {display}" via `convertViaRates(balance,
  account.currency, display, rateMap)` (note: **account→display**, not
  base→display). The `<Money>` primitive (`components/primitives.tsx`) + `use-money`
  need a currency-aware variant that takes a source currency.

## 8. UI changes

- **Accounts list + detail**: balance in the **account's** currency + "≈ {display}"
  secondary (decision 2). Detail already shows the currency code (Phase 0).
- **Add-expense** (`components/add-expense-form.tsx`): **lock the entry currency to
  the selected account's currency** (decision 3) — set/replace the currency picker
  to follow the chosen account; drop the client `convertAmount` base computation
  (the server now derives `amount_base` from the locked rate table).
- **Transfers** across differing currencies: surface both legs' currencies + rate.
- **Net worth headline**: label the spot-valued total "at today's rates".

## 9. Risks & edge cases

- **Changing `ledger.base_currency`** forces recompute of every `amount_base`
  (already flagged, `database_design_en.md:253-254`). Out of scope, but the
  recompute helper from §5 should be reusable for it.
- **Split invariant** (Σ splits = parent) must hold in **base**.
- **Net-worth ambiguity**: spot headline vs locked series must be visibly distinct
  ("at today's rates") so a no-activity FX move reads correctly.
- **Add-expense regression**: locking entry currency to the account removes a
  currently-free-form picker — verify no flow depended on a divergent entry
  currency (today none can, given the invariant).
- **Pending vs confirmed**: unaffected; pending still excluded from balances.
- **Pre-hydration fallback**: native + "≈ display" must tolerate a missing rate
  (fall back to static `RATE`, already the pattern).

## 10. Phasing

- **Phase 1 — storage correctness (no visible change):** ✅ done. `addTransaction`
  / `insertTxRow` (transfers + recurring) / scheduled auto-post write ledger-base
  `amount_base`; balances accumulate the account-currency delta; `recomputeAccount`
  mirrors it. Seed needed no change (its accounts are all account == base). No
  backfill migration needed — existing rows are already consistent. Tests added.
- **Phase 2 — read path + native display:** ✅ done. `useMoney.toBase`/`fmtFrom`;
  `balanceSeries` on `nativeAmount`; net-worth selectors take a `ToBase` so mixed
  currencies sum in the ledger base; accounts list aggregates re-expressed to base;
  detail card shows native + "≈ display". (Headline net worth on the accounts page
  is already spot-valued because `balanceOf` converts native→base at today's rate.)
- **Phase 3 — entry UX:** ✅ done. Add-expense currency follows the selected
  account (read-only); `updateTransaction` reconverts `amount_base` on an amount
  edit. (Cross-currency *transfer* UX polish — both legs' rate inline — remains a
  nice-to-have; the math is already correct from Phase 1.)
- **Phase 4 — polish (partial):**
  - ✅ **Cross-currency transfer UX** — `selectTransfers` / `listTransfers` now
    return both legs' **native** amounts + currencies (`amount`/`fromCurrency`,
    `toAmount`/`toCurrency`); the transfers list shows the sent figure in the
    from-account currency and, when the legs differ, "→ received @ rate". (The
    transfers **detail** page still reads `LEDGER.transferGroups` mock data — a
    pre-existing wiring gap, not multi-currency-specific; left as a separate task.)
  - ↩ **Unrealized FX gain/loss** — deferred. Needs `opening_balance` projected to
    the client (today only `current_balance` is, as `AccountRow.balance`) **and** a
    cost-basis decision for the opening balance (it has no locked rate), so it's a
    real accounting-design task, not just plumbing. Invisible on seed data (no
    divergent accounts) — revisit when a divergent account exists to validate against.
  - ↩ **Base-currency-change recompute tool** — deferred. No UI/mutation exists to
    change a ledger's `base_currency` today; the design doc (`database_design_en.md:253`)
    flags it as a "significant operation" requiring a recompute of every
    `amount_base`. Heavy and rare; out of scope for this pass.

## 11. Test plan

- `addTransaction`: a JPY account in a USD ledger stores `amount_base` in **USD**
  and accumulates the **¥** balance natively.
- `recomputeAccount`: that account ends at the right **¥** balance.
- Net worth: USD + JPY accounts → series in locked base; headline matches spot
  revaluation of native balances at today's rate.
- `categorySpend` / `monthlyCashflow`: mixed-currency accounts aggregate correctly
  in base.
- Backfill recompute: a pre-divergence db is unchanged (no-op) — balances and
  bases identical before/after.
- (Note: `lib/db/mutations.test.ts` "migrate … pre-versioning db" currently fails
  on `no such table: budgets` — pre-existing, unrelated; fix or quarantine before
  layering new tests.)

## 12. Open questions

All three product forks are resolved in §0. Remaining implementation-level choices
(naming of the currency-aware `<Money>` variant; whether the spot headline
converts account→base→display or account→display directly) are mechanical and can
be settled in Phase 2.
