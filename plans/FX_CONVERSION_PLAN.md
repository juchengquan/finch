# FX / cross-currency conversion — design plan

Status: **Phase 1 + 2 implemented.** Companion to `SQLITE_INTEGRATION_PLAN.md` §6.
- ✅ **Phase 1** — `lib/db/queries/rates.ts` (`rateToSgd` + `convertToBase`, SGD
  pivot, nearest-on-or-before, static fallback); `addTransaction` converts
  native→base and locks the rate.
- ✅ **Phase 2** — seed bases for foreign rows are derived from the table (fixed
  per-account opening recomputed from the seed's derived bases, so balances still
  land on the known seed balance); `createTransfer` converts the incoming leg;
  rate coverage extended to the FX seed date.
- ↩ **Remaining**: broader/real rate history, a rate-admin affordance, and whether
  `useMoney` display conversion should move off the static map (§7).

## 1. Goal

Convert a foreign-currency entry into the active ledger's **base currency** using
**real, dated rates** from the `exchange_rates` table, and **lock** that rate on
the transaction at import. Replace the static, USD-pivot guess used today.

Non-goal: live/online rate fetching, or re-deriving historical base amounts from
today's rate (the locked rate is the source of truth once a row is written).

## 2. Current state

- **Display + entry conversion uses a static map.** `lib/data.ts` exports
  `RATE` (units per 1 USD: `USD 1, EUR .92, GBP .79, JPY 156.4, SGD 1.35, CNY 7.24`)
  and `convertAmount(amount, from, to)` which pivots through USD. `add-expense-form`
  computes `amountBase = convertAmount(native, currency, base)` on the client and
  passes it to the server.
- **The server trusts the client's base amount.** `queries/transactions.addTransaction`
  stores `amount` (native), `amount_base` (client-supplied), and derives
  `exchange_rate = amount_base / amount`. Seed rows (`insertTransactions`) do the
  same from the JSON's `amount`/`nativeAmount`.
- **The real rate table is to-SGD only.** `exchange_rates(date, currency,
  rate_to_sgd, source)` — 16 rows, currencies `JPY/CNY/USD/EUR`, several dates.
  It is **projected** to the store already (`store.exchangeRates`) and drives the
  System + FX screens.
- **Ledger bases vary:** `personal=USD`, `family=SGD`, `business=CNY`, `travel=JPY`
  (`data/ledgers.json`). So conversions are genuinely cross-base, not all to-SGD.

## 3. The hard part

`exchange_rates` only stores `rate_to_sgd`. To convert an amount in currency **C**
to a ledger base **B** we pivot through SGD:

```
rate(C→B, date) = rate_to_sgd(C, date) / rate_to_sgd(B, date)
amount_base     = round( native * rate(C→B, date), 2 )
```

This requires `rate_to_sgd` coverage for **both** the entry currency and the
ledger's base currency, on (or before) the transaction date:

- `rate_to_sgd(SGD)` is implicitly `1` (add it explicitly, or special-case).
- The base currencies in use are `USD/SGD/CNY/JPY`; the table already has `USD`,
  `CNY`, `JPY` rows but coverage is sparse and date-limited.
- Dates won't align exactly → use the **nearest rate on or before** the date,
  with a documented fallback when none exists.

## 4. Decisions (proposed)

1. **SGD is the pivot** (matches `rate_to_sgd`). `rate_to_sgd(SGD) = 1`.
2. **Convert server-side**, in one helper, used by `addTransaction`, the seed's
   `insertTransactions`, and `createTransfer`. The client stops computing
   `amount_base` (it may still preview using the static map).
3. **Lock at import**: store `amount_base`, `exchange_rate` (the resolved C→B
   rate), and `exchange_rate_date` (the rate row's date) on the transaction —
   columns already exist. Reads never re-derive.
4. **Rate resolution**: nearest `exchange_rates` row for the currency with
   `date <= txnDate`; if none, fall back to the static `RATE` map and tag the row
   (`source='fallback'` via a note or a flag) so gaps are visible, not silent.
5. **Coverage**: extend `data/exchange-rates.json` so every (base currency, entry
   currency) pair used by the seed resolves without fallback.

## 5. Work breakdown

- **`lib/db/queries/rates.ts`** — `rateToSgd(exec, currency, date)` (nearest
  on-or-before; `SGD→1`), and `convertToBase(exec, native, currency, base, date)`
  returning `{ amountBase, rate, rateDate }`.
- **Wire writes** — `addTransaction`, `insertTransactions`, `createTransfer` call
  `convertToBase` instead of trusting client `amountBase` / assuming rate 1.
- **Seed data** — add `rate_to_sgd` rows so `USD/CNY/JPY/EUR` (and `SGD=1`) resolve
  for the seed transaction dates; keep the existing FX seed row (`t-jpy-1`) but let
  its base be **derived** rather than hard-coded.
- **`useMoney` display path** — decide whether display conversion (active base →
  display currency) also moves to table rates or stays on the static map (it is a
  cosmetic, "today's rate" conversion, so static is defensible — call it out).
- **Tests** — `convertToBase` (same-currency, SGD base, cross-base via pivot,
  nearest-date selection, missing-rate fallback, rounding); a seed assertion that
  `t-jpy-1`'s derived base matches the locked rate.

## 6. Edge cases & risks

- **Missing/sparse rates** → fallback path must be correct and visible.
- **Cross-base rounding**: round once, at base, to 2dp; avoid double rounding via
  the pivot.
- **Balance invariant**: seed `openingBalance` is derived from `Σ amount_base`; if
  the seed's base amounts change (now derived), opening balances shift but current
  balances must still equal the known seed balances — verify the seed tests.
- **Multi-base reporting**: `categorySpend` / net worth already sum `amount_base`
  per ledger, so they stay correct as long as base is right per row.
- **Scope creep**: this only changes how `amount_base` is produced at write time;
  it must not alter already-stored rows.

## 7. Open questions

- Do we want a tiny **rate-admin** affordance (the System screen "Refresh" button
  is currently a toast) to add/override a rate row, or keep rates seed-only?
- Should `useMoney` display conversion unify on the table (introducing "as-of"
  semantics for display), or stay a simple static map?
