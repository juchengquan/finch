# Inspiration ideas — sourced from other personal-finance apps

Companion to `plans/FEATURE_IDEAS.md`. That doc is an internal brainstorm;
this one is an **externally-sourced** scan of what other personal-finance
apps (open-source and commercial) do that finch doesn't yet — narrowed to
ideas that respect finch's constraints (single-user, single-device,
server-side SQLite, no auth, no Plaid/OFX, no multi-device sync).

Last updated: 2026-06-05.

Apps surveyed:

- **OSS / freemium**: Actual Budget · Firefly III · Maybe Finance · Lunch Money
- **Plain-text accounting**: Beancount · Fava (Beancount UI) · hledger ·
  plaintextaccounting.org cookbook
- **Premium commercial**: YNAB · Monarch · Copilot · Pocketsmith · Quicken
  Simplifi
- **Niche / specialty**: Wallos (subscriptions) · Tiller (spreadsheet PFM) ·
  Empower (wealth dashboard) · MoneyWiz · Bilance · Spendee

For each item below: **a one-line pitch**, the competitor that does it
well (cited), and a `(S/M/L · schema?)` annotation. Items already in
`FEATURE_IDEAS.md` or shipped are not repeated.

---

## 1. Reconciliation & data hygiene

### 1.1 Reconcile-to-statement workflow 🔥 S
Guided mode: user enters "I have $X at this date" on an account → app
walks through clearing transactions until the ledger matches the
statement, optionally posts an Adjustment for the gap. Currently every
edit silently shifts history — there's no green/red checkpoint. Inspired
by Actual's reconciliation flow ([Actual docs](https://actualbudget.org/docs/accounts/reconciliation/))
and Beancount's `balance` assertion idiom ([Beancount](https://beancount.github.io/docs/balance_assertions_in_beancount.html)).
Could store `last_reconciled_at` + `last_reconciled_balance` on
`accounts` for a "47 days since reconcile" badge à la Fava
([Fava features](https://github.com/beancount/fava/blob/main/src/fava/help/features.md)).

### 1.2 Activity gap detection ⚡ S
Insights rule that flags silent windows in the ledger — "no transactions
logged for 11 days". finch's insights engine already has the shape
(`lib/insights.ts`), so this is one more rule. hledger's `activity`
histogram is the conceptual parent ([hledger man](https://manpages.ubuntu.com/manpages/focal/man1/hledger.1.html)).

### 1.3 Monthly balance snapshots, editable ⚡ S 🗄️
Snapshot each account's balance at month-end into a historical series the
user can hand-edit to fix gaps (useful when joining mid-history or
importing partial data). Lunch Money ships this verbatim
([Lunch Money docs](https://support.lunchmoney.app/setup/accounts/managing-accounts)).
New `account_snapshots(account_id, month, balance, note)` table.

---

## 2. Budgeting innovations

### 2.1 Cover overspending one-tap (YNAB) 🔥 S
When a budget category goes red, a "Move from…" button lets the user pull
the gap from any other category in one action. Reframes overspend as
"the plan changed", not "you failed". Finch already has named budgets
with rollover — the data layer carries it; this is purely UI + a
mid-cycle `pending_amount` transfer.
([YNAB support](https://support.ynab.com/en_us/overspending-in-ynab-a-guide-ryWoxEyi))

### 2.2 Custom budget periods (paycheck cycle) ⚡ S
Today every cycle is calendar-aligned (monthly, biweekly, etc. anchored
to start_date). Lunch Money lets the period match a real paycheck cadence
that doesn't fall on the calendar grid
([Lunch Money budgeting](https://lunchmoney.app/features/budgeting/)).
`lib/budgets/period.ts` already abstracts cycle math; the work is making
"period start day" configurable per budget.

### 2.3 Flex Budgeting mode (Monarch) ⚡ M
Alternative budget mode that buckets categories into Fixed / Flexible /
Non-monthly and surfaces a single "flex left this month" number. For
users who don't want 20 envelopes but still want guardrails.
([Monarch help](https://help.monarch.com/hc/en-us/articles/360048883631-Creating-Your-Budget-in-Monarch))
Could ride on the existing `budgets.kind` column with a new `flex` type
or a `bucket` enum on the budget row.

### 2.4 Category groups with shared budget + rollover ⚡ M 🗄️
Lunch Money treats a category group as a budget envelope: the group
holds a single budget number and rolls over as a unit, while child
categories are reporting-only inside it
([Lunch Money setup](https://support.lunchmoney.app/setup/categories)).
finch has 2-level categories but only leaf-level budgets. Could let a
parent category carry the budget and split spend reporting under it.

---

## 3. Forecasting & scenarios

### 3.1 Long-horizon scenarios on accounts 🔥 M
finch ships 30/60/90-day account forecasts (PR #76). Pocketsmith extends
the same idea to **10/30 years** and adds **scenarios** — clone the
forecast, edit one assumption ("income drops 6 mo", "lump-sum purchase
Q3"), compare side-by-side without touching reality
([Pocketsmith features](https://www.pocketsmith.com/features/),
[forecast docs](https://learn.pocketsmith.com/article/1246-using-the-calendar-and-forecast-graph)).
Reuses `accountForecast` selector; scenarios live in `app_state` as
overrides applied at render.

### 3.2 Bills with min/max expected range ⚡ S 🗄️
Today scheduled templates have a fixed amount or an "amount varies" flag.
Firefly III defines a bill as `(min, max, expected_frequency)` so the
app can flag both **missed** bills AND bills that fell **outside the
typical range** (utility spike, late subscription)
([Firefly docs](https://docs.firefly-iii.org/explanation/financial-concepts/transactions/)).
Schema: add `amount_min` / `amount_max` to `scheduled_templates`.

### 3.3 Outstanding items resolver ⚡ S
A dedicated queue for plan items that didn't reconcile — expected bill
never hit, recurring missed, schedule paused mid-cycle. Skip / match /
edit actions per row. Simplifi has this as a permanent surface in the
Spending Plan
([Simplifi docs](https://support.simplifi.quicken.com/en/articles/5735189-resolving-outstanding-items-in-the-spending-plan)).
Pure selector + UI; no schema change.

### 3.4 "Tilde" / approximate scheduled amount ⚡ S 🗄️
Mark an amount as approximate (utilities, subs that drift) so the
template still "matches" a confirmed posting within ±N% — instead of
silently treating drift as a separate transaction. Actual uses a `~`
prefix idiom ([Actual schedules](https://actualbudget.org/docs/schedules/)).
Schema: add `amount_approx INTEGER` (boolean) to scheduled_templates.

---

## 4. Rules & automation (low-LLM)

### 4.1 Conditional rules (amount thresholds, AND/OR) 🔥 M 🗄️
finch's category suggestion (PR #73) is local heuristic only. Lunch
Money and Tiller's AutoCat support **conditional rules** —
`merchant:"Shell" AND amount<$5 → Snacks, else Fuel`. Goes beyond a
flat counterparty→category map
([Lunch Money rules](https://lunchmoney.app/features/rules)).
New `rules` table; a rule engine runs at insert + on demand against
existing rows.

### 4.2 "Find recurring" — scan history, propose templates ⚡ S
Selector over the transaction list that spots same-merchant +
similar-amount + ~30-day cadence and proposes a draft scheduled
template the user accepts in one tap. MoneyWiz calls it Auto-Detect
Bills ([MoneyWiz release notes](https://help.wiz.money/en/articles/4492243-release-notes)).
Pure heuristic; no schema change.

### 4.3 Payee merge with auto-rule promotion ⚡ S
Merging two counterparties (already possible in finch — partially)
should offer to create a rename rule so future inserts collapse to the
canonical name without manual fixup. Actual ships this in the Payees
page ([Actual payees](https://actualbudget.org/docs/tour/payees/)).
Builds on the rule engine from #4.1.

### 4.4 Auto-split rule on income ⚡ M
"When income lands in Checking, allocate 60% to spending / 20% to
savings / 20% to taxes." Profit First is the canonical recipe
([Profit First in plain-text accounting](https://blog.emacsen.net/profit-first-plain-text-accounting.html)).
Surfaces as a special rule kind that creates the matching transfer set
on income post.

---

## 5. Transaction lifecycle

### 5.1 Reviewed / unreviewed status 🔥 S 🗄️
Beyond pending (= unconfirmed). Every row carries a `needs_review` flag
that auto-clears when the user touches the row, or based on settings
("auto-review under $5"). One-tap "Mark reviewed" at the top of the
detail sheet. Lunch Money and Monarch both lean on this as the primary
triage UX
([Lunch Money status](https://support.lunchmoney.app/finances/transactions/transaction-status),
[Monarch review](https://www.monarch.com/whats-new/quicker-and-easier-transaction-review-and-more)).
Schema: `transactions.reviewed_at` nullable timestamp.

### 5.2 Pending refund tracking ⚡ S 🗄️
Mark a refund as **expected** so it shows in projected cashflow and the
outstanding-items queue until the actual refund posts (then matched).
Simplifi treats this as first-class
([Simplifi refunds](https://support.simplifi.quicken.com/en/articles/4606217-tracking-refunds-in-quicken-simplifi)).
Schema: `transactions.expected_refund_amount` or a status enum
extension.

### 5.3 Cancellation reminder (N days before next renewal) ⚡ S 🗄️
finch's scheduled templates already know when the next post is due. Add
a per-template `notify_days_before` field; surface "renews in 5 days —
cancel by 12/03" on the Scheduled page and as an insights card. Wallos
is the cleanest implementation ([Wallos](https://wallosapp.com)).

### 5.4 Split into N equal payments across a period ⚡ S
Spread one charge into N equal dated children (e.g., annual insurance
amortized monthly across the next 12 months). Lunch Money has this as a
dedicated split variant
([Lunch Money transactions](https://lunchmoney.app/features/transactions)).
Builds on existing `transaction_splits`; just adds a wizard that
generates the dated rows.

---

## 6. Investment, net worth & assets

### 6.1 Asset / liability account types ⚡ M 🗄️
Maybe Finance has first-class **property, vehicle, loan, crypto**
account kinds, so net worth includes the car and the mortgage, not just
bank balances ([Maybe README](https://github.com/maybe-finance/maybe)).
Extends `accounts.type` enum + light per-type detail UI (purchase price
+ current value for assets; principal + APR + payment for loans).

### 6.2 Cost vs market value toggle (holdings + net worth) ⚡ S
Beancount and hledger both ship a one-button flip between "value at
cost" and "value at market" ([Beancount](https://beancount.github.io/docs/),
[hledger man](https://manpages.ubuntu.com/manpages/focal/man1/hledger.1.html)).
finch already locks `cost_basis` on `holdings`; just expose the toggle on
the investment account detail + the net-worth metric tab on Insights.

### 6.3 Portfolio-level ROI metric ⚡ M
hledger has a built-in `roi` command that computes time-weighted and
money-weighted returns from the posting stream
([hledger man](https://manpages.ubuntu.com/manpages/focal/man1/hledger.1.html)).
Would slot in next to the unrealized-FX line on investment-account
detail.

### 6.4 Emergency-fund target with band ⚡ S 🗄️
Per-account or per-ledger "target cushion" with an under/over band
visualized on the account-detail balance card. Empower's emergency-fund
chart is the inspiration
([Empower](https://choosefi.com/review/empower-review-the-ultimate-net-worth-tracker)).
Schema: `accounts.cushion_target` REAL nullable.

---

## 7. Polish & UX delight

### 7.1 Tokenized search syntax in Activity ⚡ S
Power-user search bar that parses `Apple; >100; >01/01/2024` into
combined filters (merchant + amount + date) without modal filter
panels. MoneyWiz ships this exact syntax
([MoneyWiz filters](https://help.wiz.money/en/articles/4440669-how-to-filter-transactions)).
Already-existing filters; only a parser is new.

### 7.2 Category color + emoji per row ⚡ S 🗄️
finch has `categories.color` but no icon-or-emoji per category. Copilot
lets each category carry a color **and** an emoji, then skins the whole
app with those tokens — far more glanceable than a single hex
([Copilot quickstart](https://help.copilot.money/en/articles/11157550-quick-start-guide)).
Schema: `categories.emoji TEXT`.

### 7.3 Logo auto-search for counterparties ⚡ S
When a new counterparty is created, attempt a one-shot lookup (e.g. the
Clearbit logo API, or DuckDuckGo's domain favicon) for a logo URL.
Wallos does this on subscription add
([Wallos](https://wallosapp.com)). Schema:
`counterparties.logo_url`. Network call is opt-in and cached.

### 7.4 Inline "create rule" prompt after edit ⚡ S
When the user manually recategorizes a row, a non-blocking pill appears:
"Always categorize Whole Foods as Groceries?" → one tap creates the
forward-applying rule. Builds on #4.1. Copilot does this as their core
learning loop
([Copilot transactions FAQ](https://help.copilot.money/en/articles/10761907-transactions-faq)).

---

## My picks if forced

The four I'd ship next if budgeting effort/payoff:

1. **#1.1 Reconcile-to-statement** — the highest-leverage data-hygiene
   feature. Tiny UI, big trust gain. Pairs nicely with #1.3 snapshots
   and a "last reconciled N days ago" badge.
2. **#4.1 Conditional rules** — unblocks #4.2 (find recurring), #4.3
   (merge → rule), #4.4 (income split), and #7.4 (inline prompt). A
   small rule engine + a one-row `rules` table opens a whole theme.
3. **#5.1 Reviewed/unreviewed status** — a single column flip in the
   schema; transforms Activity from "scroll forever" into a real triage
   queue. Most-used flow in Lunch Money and Monarch for a reason.
4. **#3.1 Long-horizon scenarios** — extends the already-shipped
   `accountForecast` (PR #76) to 12/24/60-month and adds scenario
   overlays. The natural next step for the forecasting theme.

Bonus low-cost pick:

5. **#6.2 Cost vs market value toggle** — one button on Insights' net-
   worth tab + holdings panel. Code is already there; just expose it.

These five are deliberately the lower-schema-impact end of the list; the
bigger swings (asset/liability accounts, Flex budgeting mode, category
groups with shared budgets) deserve their own scoping doc once the
above are in.
