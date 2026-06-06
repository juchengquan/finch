# Feature ideas — what could make finch a killer app

A brainstorm catalog of features beyond the current roadmap. Not a plan — an
inventory of ideas worth scoring against effort/impact when the next
planning conversation happens. Items are grouped by theme; within each
theme I've tagged a rough effort estimate (S/M/L) and impact (low/med/high)
and noted whether anything in the DB schema would need to change.

> **Scope reminder.** finch is server-side SQLite, offline-capable, no
> external APIs, no multi-user, no live bank feeds. Everything below
> respects those constraints.

---

## How to read this

| Tag | Meaning |
|---|---|
| **S** | < 1 PR / half-day / ~100 LOC |
| **M** | 1 focused PR / 1–2 days / ~300 LOC |
| **L** | Multi-PR / 1+ week / new schema |
| 🔥 | High impact — would change how the app feels day-to-day |
| ⚡ | Medium impact — meaningful win for the people who hit it |
| · | Niche / loud-fanbase win |
| 🗄️ | Requires a schema change |

---

## 1. Quality-of-life on the entry flow

The Add screen is the most-tapped surface. Anything that saves a tap here
compounds across thousands of entries.

### 1.1 Repeat last expense 🔥 S
One-tap re-add of your most-recent identical transaction (the daily coffee,
the lunch place, the parking meter). Today: 5 taps. With this: 1. Pure UI;
no schema.

### 1.2 Recurring template autofill ⚡ S
When the user types a description that matches an existing scheduled
template, offer "this looks like Spotify Premium — convert to scheduled?"
Discoverability today is poor; users don't realize templates exist.

### 1.3 Smart-defaults for date / account / category ⚡ S
The form defaults to today and the previous account. Could go further:
default to "the account most often used at this time of day". Tiny
behavioral nudge, free win.

### 1.4 Voice entry ⚡ M
"Twelve dollars at Starbucks just now" → parsed merchant/amount via Web
Speech API → confirm sheet. Pure browser API, no service dependency. Great
for hands-busy moments (driving, walking).

### 1.5 OCR receipt → transaction ⚡ L
Snap a photo of a receipt → extract merchant, date, total via
WebAssembly-based Tesseract or a small browser OCR model. Confirm sheet,
then save. Higher effort; non-trivial accuracy work.

### 1.6 Multi-add (queue mode) · S
After saving, the form stays open with date/account preserved — for
processing a stack of receipts in one sitting. Optional toggle.

---

## 2. Forecasting & proactive intelligence

The data layer already knows what's coming (scheduled + recurring + average
patterns). Almost nothing surfaces it.

### 2.1 30/60/90-day cashflow forecast 🔥 M
A single screen: timeline showing your Checking balance projected forward
based on scheduled debits/credits. "Rent on the 1st: −$1850. Salary on the
15th: +$2900. Spotify on the 22nd: −$12." Critical for anyone living close
to the bone.

### 2.2 Low-balance alarm 🔥 S
Proactive: "Checking will drop below $500 on June 12." Per-account
configurable floor; surfaces on the Insights page and (PWA) push
notification. Prevents real overdraft pain.

### 2.3 Income smoothing for variable earners ⚡ M
For freelance/gig users with lumpy income, a "you can spend $X this month
without dipping into reserve" calc based on rolling 6-month average + a
buffer floor. Set the floor once; the headline updates monthly.

### 2.4 Forecasted year-end position ⚡ S
"At current burn, your savings will hit $X by Dec 31." Pure extrapolation
of the existing trend lines.

### 2.5 Spending velocity warning ⚡ S
"You've spent $300 today; your average is $40/day." In-day prompt for
unusual splurges, dismissible.

---

## 3. Anomaly & insight

Turn the data into wisdom rather than just a ledger.

### 3.1 Per-merchant anomaly detector 🔥 M
Z-score over each merchant's amount history. "$89 at Bali Beach Club is 3×
your average tab — confirm?" Catches both fraud and "wait, that was
expensive". Pure heuristic, no model.

### 3.2 Weekly digest 🔥 M
Monday morning card: "Last week: $387 food (vs $310 avg), $42 rides (3
trips), $0 income. Weekly spend $429 vs typical $580." Optional PWA push
("digest ready"). Turns the app into something you *check on*, not just
*log into*.

### 3.3 "What-if" sliders on Insights ⚡ M
"If I cut dining out by 30% I'd save $1,440/year." "At this savings rate,
$50k in 2.1 years." Interactive hypotheticals over real data.

### 3.4 Spending pattern surfacer ⚡ M
"You spend ~$60 on Saturdays vs $20 weekdays." "You spend 2× as much on
food on rainy days." Pure SQL aggregation by day-of-week / month /
weekday-vs-weekend. Tiny insights, fun to see.

### 3.5 Year-over-year compare ⚡ S
"June 2026 vs June 2025: +$120 on dining, −$340 on rent (moved)." Pure
groupby. Powerful at month-end.

### 3.6 Net-worth milestones ⚡ S
Celebrate hitting $10k / $50k / $100k. Annual review: "You grew net worth
by $X this year, here's the path." Lightweight gamification.

### 3.7 Subscriptions audit ⚡ S
Detect recurring patterns (same merchant, same amount, monthly cadence) and
surface them as "You're paying $147/month across 8 subscriptions. Last new
one: Notion, May." Highlight ones you might have forgotten.

### 3.8 Spending streaks · S
"5 days without buying lunch out." "12 days since an Amazon order." Light
habit tracking; toggle to opt out of moralizing.

### 3.9 Category creation suggestions · S
"You've filed 23 things as 'misc' that look food-related — make a 'Pet'
category?" Periodic, dismissible.

---

## 4. Receipts, photos, attachments

### 4.1 Receipt photo per transaction 🔥 M 🗄️
Attach an image to a transaction, stored in OPFS (no upload). "What was
that $42 at Target six months ago?" becomes answerable. Schema: a new
`transaction_attachments` table.

### 4.2 Searchable notes ⚡ S
The `notes` field already exists; surface it in FTS5 so notes are
queryable. Likely already covered by the FTS5 shadow — verify.

### 4.3 Tag from URL ⚡ S
Paste a URL (Amazon order page, Shopify confirmation) into notes; we
extract the order number and merchant for fast matching later. Schema-free.

---

## 5. Sharing & collaboration

The Family ledger covers shared accounts; nothing today handles ad-hoc
splits between friends.

### 5.1 "Split this with Sam" within Personal ledger 🔥 L 🗄️
A real Splitwise replacement *inside* finch. Mark a transaction as "shared
50/50 with Sam"; track who-owes-who; settle with a transfer that closes the
loop. New `splits_with` table or extension of `transaction_splits`.

### 5.2 Group expense pool ⚡ L 🗄️
For a one-week trip with 4 friends: a shared mini-ledger, anyone adds
expenses, app calculates settlement at the end. Could fold into the
existing ledger model.

### 5.3 Export-to-share ⚡ S
Generate a one-page PDF/PNG of a custom date range for accountability
partners or bookkeepers. Could be markdown-rendered.

---

## 6. Goals & motivation

The Goals concept was folded into Budgets (one-shot income type). Could
re-elevate without re-splitting the model.

### 6.1 Visual savings goal with milestones ⚡ M
"You're 67% of the way to your $5,000 emergency fund. At $200/month, ETA
is February." Optional cover image, milestone celebrations at 25/50/75%.

### 6.2 Multi-goal dashboard ⚡ S
A single screen with all your goals (existing budget-income rows) at a
glance, ranked by ETA or % complete.

### 6.3 FIRE / retirement projection · M
Optional: "At your current savings rate, you'd hit financial independence
in 14 years." Single screen, fully parameterized by your real numbers.

### 6.4 Net-worth annotations ⚡ S
On the net-worth chart: annotate "Got bonus", "Bought house", "Started
new job" at specific dates. Stored as a tiny `chart_annotations` table or
piggybacks on transactions.

---

## 7. Power-user tools

For the users who live in the app.

### 7.1 Bulk recategorize from search results 🔥 S
"Find all 47 Whole Foods transactions" → "Set category = Groceries on all
of them." Every user has at least one persistent miscategorization eating
reports.

### 7.2 Saved searches / smart filters ⚡ S — ✅ shipped (PR #89)
Pin "subscriptions > $20" or "uncategorized last 30d" as chips. Gmail
labels for transactions. Shipped client-only (localStorage, per-ledger);
see MASTER_PLAN "Saved searches" for the implementation + the ⌘K-palette
no-go.

### 7.3 Locking past periods ⚡ S 🗄️
"This month is closed, don't edit." Prevents accidental drift on reconciled
periods. New `is_locked` flag on a `periods` table or stored per-month in
`app_state`.

### 7.4 Duplicate transaction detector ⚡ S
Same amount, same merchant, within 24 hours → flag for review. Critical
once any import is enabled; useful even for manual entry.

### 7.5 Audit trail per transaction · S 🗄️
"Edited 2× — was $42 (May 1), changed to $45 (May 3)." Useful for
forensics. Schema: a `transaction_edits` log.

### 7.6 Hierarchical tags · M
Tags currently flat. "work > clients > acme" would let reports roll up
without choosing between "fine-grained tag" and "broad tag".

### 7.7 Tag rules ⚡ M
"Auto-tag every transaction at Whole Foods with #groceries." Rule
evaluated at insert/edit time. Becomes a poor-person's category
suggestion fallback.

### 7.8 Account-level monthly statement ⚡ S
Per-account, per-month: opening balance, every transaction, closing
balance. Useful for reconciling against bank statements.

### 7.9 Keyboard shortcuts everywhere · S
"a" = add, "s" = search, "/" = jump-to-account. Already partially via ⌘K;
extend.

### 7.10 Custom dashboards ⚡ L
Pin specific charts/numbers to a personal dashboard. Today every user
gets the same Insights page; advanced users want to curate.

---

## 8. Reports & data export

### 8.1 Annual tax report ⚡ M 🗄️
Export full-year totals by category. Mark categories as "tax-relevant"
(new bool on `categories`). One report page filtered to those + CSV
export. Already on the master plan.

### 8.2 Cash withdrawals breakdown · S
When tagged as "ATM", track an estimated "where the cash went" via a
sibling notes field. Half-feature, half-acknowledgment that cash is
opaque.

### 8.3 Schedule C-style P&L for freelancers ⚡ M
Income − business expenses, grouped by category, with date range filter.
Builds on tax categories + the business ledger.

### 8.4 Scheduled exports ⚡ S
Auto-download a CSV every month, written to OPFS or triggered as a
File-Save dialog. Not magic — just the existing CSV export on a cron.

---

## 9. Big swings (more scope, more payoff)

### 9.1 Local LLM categorization fallback ⚡ L
When the heuristic (PR #73) returns null on a new merchant, run a tiny
browser-side model to guess based on the merchant name. WebGPU + ~50MB
model. Fully offline. Bigger build; bigger payoff for first-time
merchants.

### 9.2 Multi-device sync via DB diffs ⚡ L 🗄️
Explicitly out of scope today (export/import is the cross-device story).
A real sync would need event logs + conflict resolution. Big system
design lift.

### 9.3 Bank CSV / OFX import ⚡ M
Read-only CSV import from your bank's downloaded statement. Map columns,
de-dupe against existing entries, flag conflicts. Closes the "but my bank
gives me a file" gap for users who don't want manual entry.

### 9.4 Privacy mode (blur amounts) ⚡ S
One-tap blur for showing the app on a train. Lightweight; high
"feels professional" payoff.

### 9.5 Travel mode (auto-trip detection) · M
Auto-cluster transactions by date range (or location, if we had it) into
a per-trip mini-report. "Day 3 Tokyo: ¥18,420 across 5 charges." Lives
between Personal and Travel ledgers.

### 9.6 Investment expansion (dividends, performance vs benchmark) ⚡ L 🗄️
On top of the holdings table: track dividends per holding, benchmark
against an index (SPY default), compute time-weighted return. Bigger
investment-side build.

### 9.7 Tax-loss harvesting hints · M
For investment accounts: when a holding's unrealized loss exceeds $X,
surface "selling this would realize a $Y loss for tax purposes." Niche
but loved by the audience that needs it.

---

## 10. Chart primitives still on the original design list

### 10.1 CalendarHeatmap · M
A year-grid of daily spending intensity (like GitHub contributions). On
the master plan; not built.

### 10.2 Multi-series AreaChart · M
Stacked areas for income vs. expense by category over time. On the master
plan; not built.

---

## 11. PWA prerequisites & follow-ons

### 11.1 PWA implementation ⚡ M
Already scoped in `PWA_PLAN.md`. Once shipped, several items above
become viable: push notifications for the digest (3.2) and low-balance
alarm (2.2), installable shortcut for repeat-last (1.1), etc.

### 11.2 Push notifications for digest + alarms · S (after PWA)
Weekly digest + low-balance + bill-due notifications. Requires PWA. Each
one is small once the SW infrastructure exists.

---

## My picks if forced

| Pick | Why |
|---|---|
| **#1.1 Repeat last expense** | Smallest killer feature you could ship. Daily-use win. |
| **#2.1 30/60/90-day cashflow** | Biggest "wait, why didn't this exist already" moment. |
| **#4.1 Receipt photos** | Highest emotional payoff per build cost. |
| **#3.1 Per-merchant anomaly** | Subtle but valuable — catches both fraud and "huh, was it really $89?" |
| **#7.1 Bulk recategorize** | Every user benefits from this exactly once, but they remember it forever. |

If you want one to ship in a single session, **#1.1** is the call. If you
want one that defines the next phase, **#2.1**.

---

## Roadmap pose

If we were ordering this for the next 6 months, a plausible shape:

1. **Quick wins phase** — Repeat last (1.1), Bulk recategorize (7.1) ✅,
   Saved searches (7.2) ✅, Spending velocity warning (2.5). Each S; all
   together = one PR each, week of work.
2. **Cashflow phase** — 30/60/90 forecast (2.1), Low-balance alarm
   (2.2), Subscriptions audit (3.7). M each; 2–3 weeks.
3. **PWA phase** — Implement the existing plan, unlock push for digest
   + alarms. 1 week core + 1 week notifications.
4. **Insight phase** — Weekly digest (3.2), Anomaly detector (3.1),
   What-if sliders (3.3), Year-over-year compare (3.5). M each; 2–3
   weeks.
5. **Data enrichment phase** — Receipt photos (4.1), Tax report (8.1),
   Audit trail (7.5). 2–3 weeks.
6. **Big swings, picked one** — Splitwise (5.1) OR LLM categorization
   (9.1) OR Bank CSV import (9.3) — depends on which user pain
   dominates feedback.

The CalendarHeatmap / AreaChart (§10) primitives slot in opportunistically
whenever the relevant screen gets touched.
