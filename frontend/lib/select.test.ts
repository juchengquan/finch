import { test, expect } from 'bun:test';
import { balanceSeries, netWorthSeries, categorySpend, monthlySpending, monthlyCashflow, topCategoryDeltas, dailySpending, netWorthByMonth, selectTransactions, monthForecast, incomeCategoryFlow, unrealizedFx, holdingValue, holdingGainLoss, holdingsForAccount, holdingsValueForAccount, investmentAccountTotal, suggestCategory } from "@/lib/select";
import type { Holding } from '@/lib/db/queries/holdings';
import type { Tx, ScheduledTemplate } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';

const tx = (over: Partial<Tx>): Tx => ({
  id: Math.random().toString(36).slice(2),
  merchant: 'm',
  category: 'food',
  amount: -10,
  account: 'cc',
  date: '2026-05-01',
  pending: false,
  ledgerId: 'personal',
  ...over,
});

const acct = (over: Partial<AccountRow>): AccountRow => ({
  id: 'cc',
  ledgerId: 'personal',
  name: 'cc',
  type: 'credit_card',
  currency: 'USD',
  balance: 0,
  openingBalanceBase: 0,
  groupId: null,
  groupName: null,
  includeInNetWorth: 1,
  color: null,
  sortOrder: 0,
  ...over,
});

test('balanceSeries ends at the current balance and walks back to opening', () => {
  const txns = [tx({ amount: -10, date: '2026-05-01' }), tx({ amount: -20, date: '2026-05-02' })];
  const s = balanceSeries(txns, 'cc', 100);
  expect(s[0]).toBe(130); // opening = 100 − (−30)
  expect(s[s.length - 1]).toBe(100);
  expect(s.length).toBe(3);
});

test('balanceSeries only counts the requested account', () => {
  const txns = [tx({ amount: -10, account: 'cc' }), tx({ amount: -20, account: 'chk' })];
  const s = balanceSeries(txns, 'cc', 50);
  expect(s.length).toBe(2);
  expect(s[s.length - 1]).toBe(50);
});

test('netWorthSeries ends at the ledger total and ignores other ledgers', () => {
  const accounts = [acct({ id: 'cc', balance: 100 }), acct({ id: 'x', ledgerId: 'family', balance: 999 })];
  const txns = [tx({ amount: -10 }), tx({ amount: 50, ledgerId: 'family' })];
  const s = netWorthSeries(txns, accounts, 'personal');
  expect(s[s.length - 1]).toBe(100);
});

test('balanceSeries walks the native (account-currency) amount when present', () => {
  // A ¥ account: the native amounts differ from the ledger-base Tx.amount.
  const txns = [
    tx({ amount: -65, nativeAmount: -10000, currency: 'JPY', date: '2026-05-01' }),
    tx({ amount: -33, nativeAmount: -5000, currency: 'JPY', date: '2026-05-02' }),
  ];
  const s = balanceSeries(txns, 'cc', -15000); // current balance in ¥
  expect(s[0]).toBe(0); // opening = −15000 − (−15000 native)
  expect(s[s.length - 1]).toBe(-15000); // ends at the native balance, not the base sum
});

const toJpyBase = (amount: number, cur: string) => (cur === 'JPY' ? amount * 0.0065 : amount);

test('netWorthSeries sums mixed-currency balances in the ledger base via toBase', () => {
  const accounts = [acct({ id: 'usd', currency: 'USD', balance: 100 }), acct({ id: 'jpy', currency: 'JPY', balance: 10000 })];
  const s = netWorthSeries([], accounts, 'personal', toJpyBase);
  expect(s[s.length - 1]).toBeCloseTo(100 + 10000 * 0.0065, 2); // ¥ converted, $ passed through
});

test('netWorthByMonth anchors the total in the ledger base via toBase', () => {
  const accounts = [acct({ id: 'jpy', currency: 'JPY', balance: 10000 })];
  const r = netWorthByMonth([], accounts, 'personal', '2026-05', 1, toJpyBase);
  expect(r[r.length - 1].v).toBeCloseTo(65, 2);
});

test('categorySpend excludes pending, transfers, and income', () => {
  const txns = [
    tx({ amount: -10, category: 'food' }),
    tx({ amount: -5, category: 'food', pending: true }),
    tx({ amount: -7, category: 'food', transferGroupId: 'tg1' }),
    tx({ amount: 20, category: 'food' }),
  ];
  expect(categorySpend(txns, 'personal').food).toBe(10);
});

test('categorySpend uses splits when present (overrides parent category)', () => {
  const txns = [
    tx({
      amount: -100,
      category: 'food',
      splits: [
        { id: 's1', categoryId: 'food', amount: -60, amountBase: -60, description: null },
        { id: 's2', categoryId: 'household', amount: -40, amountBase: -40, description: null },
      ],
    }),
    tx({ amount: -20, category: 'food' }),
  ];
  const m = categorySpend(txns, 'personal');
  expect(m.food).toBeCloseTo(80, 2);   // 60 (split) + 20 (unsplit)
  expect(m.household).toBeCloseTo(40, 2);
});

test('categorySpend skips split rows with null category', () => {
  const txns = [
    tx({
      amount: -100,
      category: 'food',
      splits: [
        { id: 's1', categoryId: 'food', amount: -70, amountBase: -70, description: null },
        { id: 's2', categoryId: null, amount: -30, amountBase: -30, description: null },
      ],
    }),
  ];
  const m = categorySpend(txns, 'personal');
  expect(m.food).toBeCloseTo(70, 2);
  expect(Object.keys(m)).toEqual(['food']);
});

test('monthlySpending sums expenses per month (excludes transfers, adjustments, pending, income)', () => {
  const txns = [
    tx({ amount: -100, date: '2026-05-15' }),
    tx({ amount: -40, date: '2026-05-18' }),
    tx({ amount: -200, date: '2026-04-10' }),
    tx({ amount: 1500, date: '2026-05-22' }), // income — skip
    tx({ amount: -25, date: '2026-05-20', transferGroupId: 'tg-1' }), // transfer — skip
    tx({ amount: -50, date: '2026-05-21', kind: 'adjustment' }), // adjustment — skip
    tx({ amount: -30, date: '2026-05-23', pending: true }), // pending — skip
  ];
  const out = monthlySpending(txns, 'personal', '2026-05', 3);
  expect(out.map((r) => r.m)).toEqual(['Mar', 'Apr', 'May']);
  expect(out[0].v).toBe(0);
  expect(out[1].v).toBeCloseTo(200, 2);
  expect(out[2].v).toBeCloseTo(140, 2);
});

test('monthlyCashflow splits income vs expense per month (both positive)', () => {
  const txns = [
    tx({ amount: 1500, date: '2026-05-01' }), // income
    tx({ amount: -200, date: '2026-05-02' }), // expense
    tx({ amount: -50, date: '2026-04-15' }),
    tx({ amount: 800, date: '2026-04-25' }),
  ];
  const out = monthlyCashflow(txns, 'personal', '2026-05', 2);
  expect(out.map((r) => r.m)).toEqual(['Apr', 'May']);
  expect(out[0].inc).toBeCloseTo(800, 2);
  expect(out[0].exp).toBeCloseTo(50, 2);
  expect(out[1].inc).toBeCloseTo(1500, 2);
  expect(out[1].exp).toBeCloseTo(200, 2);
});

test('topCategoryDeltas: % change vs prev month, sorted by absolute delta', () => {
  const txns = [
    // Food: 100 → 150 (+50)
    tx({ amount: -100, category: 'food', date: '2026-04-10' }),
    tx({ amount: -150, category: 'food', date: '2026-05-10' }),
    // Shopping: 50 → 200 (+150, bigger delta)
    tx({ amount: -50, category: 'shop', date: '2026-04-05' }),
    tx({ amount: -200, category: 'shop', date: '2026-05-05' }),
    // Transport: 80 → 0 (-80)
    tx({ amount: -80, category: 'trans', date: '2026-04-20' }),
  ];
  const cats = [
    { id: 'food', name: 'Food' },
    { id: 'shop', name: 'Shopping' },
    { id: 'trans', name: 'Transport' },
  ];
  const out = topCategoryDeltas(txns, 'personal', '2026-05', cats, 5);
  expect(out[0].name).toBe('Shopping'); // largest absolute delta
  expect(out[0].a).toBe(50);
  expect(out[0].b).toBe(200);
  expect(out[0].d).toBe(300); // (200-50)/50 * 100
  const food = out.find((r) => r.name === 'Food')!;
  expect(food.d).toBe(50);
  const trans = out.find((r) => r.name === 'Transport')!;
  expect(trans.b).toBe(0);
  expect(trans.d).toBe(-100);
});

test('dailySpending buckets expenses per day, excludes non-expense rows', () => {
  const txns = [
    tx({ amount: -10, date: '2026-05-23' }),
    tx({ amount: -5, date: '2026-05-23' }), // same day, sums
    tx({ amount: -8, date: '2026-05-24' }),
    tx({ amount: 1500, date: '2026-05-24' }), // income — skip
    tx({ amount: -3, date: '2026-05-24', transferGroupId: 'tg1' }), // transfer — skip
    tx({ amount: -7, date: '2026-05-22', kind: 'adjustment' }), // adjustment — skip
    tx({ amount: -9, date: '2026-05-21', pending: true }), // pending — skip
    tx({ amount: -2, date: '2026-04-30' }), // before window — skip
  ];
  // Window: 4 days ending 2026-05-24 → 21, 22, 23, 24.
  const out = dailySpending(txns, 'personal', '2026-05-24', 4);
  expect(out.map((r) => r.date)).toEqual(['2026-05-21', '2026-05-22', '2026-05-23', '2026-05-24']);
  expect(out[0].value).toBe(0); // pending excluded
  expect(out[1].value).toBe(0); // adjustment excluded
  expect(out[2].value).toBeCloseTo(15, 2);
  expect(out[3].value).toBeCloseTo(8, 2);
});

test('dailySpending returns [] when endDate is empty', () => {
  expect(dailySpending([], 'personal', '', 7)).toEqual([]);
});


test('netWorthByMonth ends at the current ledger total and walks back per month', () => {
  // Final total = 100 (cc); txns across Apr and May:
  // Apr: -10 + -20 = -30; May: -5 + -15 = -20. Opening = 100 - (-50) = 150.
  // End of Apr = 150 + (-30) = 120. End of May = 120 + (-20) = 100.
  const accounts = [acct({ id: 'cc', balance: 100 })];
  const txns = [
    tx({ amount: -10, date: '2026-04-05' }),
    tx({ amount: -20, date: '2026-04-15' }),
    tx({ amount: -5, date: '2026-05-10' }),
    tx({ amount: -15, date: '2026-05-25' }),
  ];
  const out = netWorthByMonth(txns, accounts, 'personal', '2026-05', 2);
  expect(out.map((r) => r.m)).toEqual(['Apr', 'May']);
  expect(out[0].v).toBeCloseTo(120, 2);
  expect(out[1].v).toBeCloseTo(100, 2);
});

test('netWorthByMonth ignores other ledgers and returns [] for empty endMonth', () => {
  const accounts = [
    acct({ id: 'cc', balance: 100 }),
    acct({ id: 'x', ledgerId: 'family', balance: 999 }),
  ];
  const txns = [tx({ amount: 50, ledgerId: 'family', date: '2026-05-10' })];
  const out = netWorthByMonth(txns, accounts, 'personal', '2026-05', 1);
  expect(out[0].v).toBeCloseTo(100, 2); // family txn ignored
  expect(netWorthByMonth([], accounts, 'personal', '', 3)).toEqual([]);
});

test('selectTransactions filters by date range (from / to inclusive)', () => {
  const txns = [
    tx({ id: 't1', amount: -10, date: '2026-05-01' }),
    tx({ id: 't2', amount: -20, date: '2026-05-15' }),
    tx({ id: 't3', amount: -30, date: '2026-06-02' }),
  ];
  const ranged = selectTransactions(txns, { ledgerId: 'personal', from: '2026-05-10', to: '2026-05-31' });
  expect(ranged.map((t) => t.id)).toEqual(['t2']);
  const openEnd = selectTransactions(txns, { ledgerId: 'personal', from: '2026-05-10' });
  expect(openEnd.map((t) => t.id).sort()).toEqual(['t2', 't3']);
});

test('selectTransactions filters by absolute amount (min / max inclusive)', () => {
  const txns = [
    tx({ id: 'a', amount: -5 }),
    tx({ id: 'b', amount: -50 }),
    tx({ id: 'c', amount: -500 }),
    tx({ id: 'd', amount: 200 }), // sign-agnostic
  ];
  const min = selectTransactions(txns, { ledgerId: 'personal', minAmount: 50 });
  expect(min.map((t) => t.id).sort()).toEqual(['b', 'c', 'd']);
  const max = selectTransactions(txns, { ledgerId: 'personal', maxAmount: 100 });
  expect(max.map((t) => t.id).sort()).toEqual(['a', 'b']);
  const both = selectTransactions(txns, { ledgerId: 'personal', minAmount: 50, maxAmount: 250 });
  expect(both.map((t) => t.id).sort()).toEqual(['b', 'd']);
});

const rt = (over: Partial<ScheduledTemplate>): ScheduledTemplate => ({
  id: Math.random().toString(36).slice(2),
  name: 'rent',
  type: 'expense',
  amount: 100,
  frequency: 'monthly',
  dayOfMonth: 1,
  accountId: 'chk',
  account: 'chk',
  autoPost: 0,
  nextRun: '',
  lastRun: '',
  ...over,
});

test('monthForecast returns null when month is empty', () => {
  expect(monthForecast([], [], 'personal', '', '2026-05-15')).toBeNull();
});

test('monthForecast: in-month projection = MTD + run-rate × days-left + upcoming', () => {
  const txns = [
    tx({ amount: -100, date: '2026-05-01' }),
    tx({ amount: -50, date: '2026-05-05' }),
    tx({ amount: -10, date: '2026-05-10' }),
    tx({ amount: -999, date: '2026-05-20' }),
    tx({ amount: -200, date: '2026-04-15' }),
    tx({ amount: -30, date: '2026-05-08', pending: true }),
    tx({ amount: -25, date: '2026-05-09', transferGroupId: 'tg-1' }),
    tx({ amount: -15, date: '2026-05-09', kind: 'adjustment' }),
    tx({ amount: 5000, date: '2026-05-01' }),
  ];
  const recurring = [
    rt({ amount: 100, dayOfMonth: 15 }), // upcoming expense
    rt({ amount: 80, dayOfMonth: 3 }), // already past — excluded
    rt({ amount: 50, dayOfMonth: 20, frequency: 'yearly' }), // wrong frequency
    rt({ amount: 30, dayOfMonth: 25, type: 'income' }), // income — excluded
    rt({ amount: null, dayOfMonth: 25 }), // variable — excluded
    rt({ amount: 60, dayOfMonth: 22, type: 'expense' }), // second upcoming expense
  ];

  const f = monthForecast(txns, recurring, 'personal', '2026-05', '2026-05-10');
  expect(f).not.toBeNull();
  expect(f!.daysInMonth).toBe(31);
  expect(f!.daysElapsed).toBe(10);
  expect(f!.daysRemaining).toBe(21);
  expect(f!.mtdSpent).toBeCloseTo(160, 2);
  expect(f!.dailyRunRate).toBeCloseTo(16, 2);
  expect(f!.unscheduledRest).toBeCloseTo(336, 2);
  expect(f!.scheduledRest).toBeCloseTo(160, 2); // 100 + 60
  expect(f!.projected).toBeCloseTo(160 + 336 + 160, 2);
});

test('monthForecast for a past month: projection collapses to actuals (no run-rate, no upcoming)', () => {
  const txns = [
    tx({ amount: -100, date: '2026-04-05' }),
    tx({ amount: -200, date: '2026-04-25' }),
  ];
  const recurring = [rt({ amount: 100, dayOfMonth: 15 }), rt({ amount: 60, dayOfMonth: 22, type: 'expense' })];
  const f = monthForecast(txns, recurring, 'personal', '2026-04', '2026-05-10');
  expect(f).not.toBeNull();
  expect(f!.mtdSpent).toBeCloseTo(300, 2);
  expect(f!.unscheduledRest).toBe(0);
  expect(f!.scheduledRest).toBe(0);
  expect(f!.projected).toBeCloseTo(300, 2);
  expect(f!.daysRemaining).toBe(0);
});

test('incomeCategoryFlow: ranks top expense categories and surfaces savings', () => {
  // 1000 income; expenses: food 200, shop 150, trans 50; net saved = 600.
  const txns = [
    tx({ amount: 1000, date: '2026-05-01', category: null }),
    tx({ amount: -200, category: 'food', date: '2026-05-05' }),
    tx({ amount: -150, category: 'shop', date: '2026-05-10' }),
    tx({ amount: -50, category: 'trans', date: '2026-05-12' }),
    // Excluded:
    tx({ amount: -30, category: 'food', date: '2026-05-15', pending: true }),
    tx({ amount: -50, category: 'food', date: '2026-04-15' }),
  ];
  const cats = [
    { id: 'food', name: 'Food' },
    { id: 'shop', name: 'Shopping' },
    { id: 'trans', name: 'Transport' },
  ];
  const flow = incomeCategoryFlow(txns, cats, 'personal', '2026-05', 6);
  expect(flow.income).toBeCloseTo(1000, 2);
  expect(flow.categories.map((c) => c.id)).toEqual(['food', 'shop', 'trans']);
  expect(flow.categories[0].spent).toBeCloseTo(200, 2);
  expect(flow.saved).toBeCloseTo(600, 2);
});

test('incomeCategoryFlow: collapses overflow into an "Other" stub', () => {
  const cats = [
    { id: 'a', name: 'A' },
    { id: 'b', name: 'B' },
    { id: 'c', name: 'C' },
    { id: 'd', name: 'D' },
  ];
  const txns = [
    tx({ amount: 500, date: '2026-05-01' }),
    tx({ amount: -100, category: 'a', date: '2026-05-02' }),
    tx({ amount: -50, category: 'b', date: '2026-05-03' }),
    tx({ amount: -30, category: 'c', date: '2026-05-04' }),
    tx({ amount: -20, category: 'd', date: '2026-05-05' }),
  ];
  // topN = 2 → expect 'a', 'b', and an Other stub of 30 + 20 = 50.
  const flow = incomeCategoryFlow(txns, cats, 'personal', '2026-05', 2);
  expect(flow.categories.map((c) => c.id)).toEqual(['a', 'b', '__other__']);
  expect(flow.categories[2].spent).toBeCloseTo(50, 2);
});

test('incomeCategoryFlow: saved is floored at 0 when expenses exceed income', () => {
  const cats = [{ id: 'a', name: 'A' }];
  const txns = [
    tx({ amount: 100, date: '2026-05-01' }),
    tx({ amount: -200, category: 'a', date: '2026-05-02' }),
  ];
  const flow = incomeCategoryFlow(txns, cats, 'personal', '2026-05', 6);
  expect(flow.saved).toBe(0);
});

// Live-rate stub for FX tests: USD account on an SGD ledger, USD → SGD at
// 1.35. toBase(amount, 'USD') returns amount * 1.35; other currencies pass
// through.
const sgdToBase = (amount: number, currency: string) => (currency === 'USD' ? amount * 1.35 : amount);

test('unrealizedFx: zero when the account is in the ledger base', () => {
  const a = acct({ id: 'sgd', currency: 'SGD', balance: 1000, openingBalanceBase: 1000 });
  // toBase is identity for the base currency — must return exactly 0.
  expect(unrealizedFx(a, [], (n) => n)).toBe(0);
});

test('unrealizedFx: opening-only — full delta when no transactions', () => {
  // Cost basis was 1000 SGD (USD 1000 × 1.0). Live rate jumped to 1.35 → 1350 SGD.
  const a = acct({ id: 'usd', currency: 'USD', balance: 1000, openingBalanceBase: 1000 });
  expect(unrealizedFx(a, [], sgdToBase)).toBe(350);
});

test('unrealizedFx: cost basis includes Σ amount_base of confirmed txns', () => {
  // Opening 1000 USD locked at 1.0 → 1000 SGD basis. Add a USD 500 deposit locked
  // at 1.2 → +600 SGD basis. Current balance 1500 USD × 1.35 = 2025 SGD.
  // Unrealized FX = 2025 − (1000 + 600) = 425.
  const a = acct({ id: 'usd', currency: 'USD', balance: 1500, openingBalanceBase: 1000 });
  const txns = [tx({ account: 'usd', amount: 600, nativeAmount: 500, currency: 'USD', date: '2026-04-01' })];
  expect(unrealizedFx(a, txns, sgdToBase)).toBe(425);
});

test('unrealizedFx: ignores pending and other accounts', () => {
  const a = acct({ id: 'usd', currency: 'USD', balance: 1000, openingBalanceBase: 1000 });
  const txns = [
    tx({ account: 'usd', amount: 200, pending: true, date: '2026-04-01' }), // pending, skipped
    tx({ account: 'other', amount: 9999, date: '2026-04-02' }),             // other account, skipped
  ];
  expect(unrealizedFx(a, txns, sgdToBase)).toBe(350); // same as opening-only
});

test('unrealizedFx: ignores txns from a different ledger even when account ids collide', () => {
  // A future shared id between ledgers shouldn't drag in the wrong rows.
  // The function takes the whole store transaction list; the ledger filter is
  // the only thing keeping the cost basis honest.
  const a = acct({ id: 'usd', ledgerId: 'personal', currency: 'USD', balance: 1000, openingBalanceBase: 1000 });
  const txns = [
    tx({ account: 'usd', ledgerId: 'personal', amount: 200, date: '2026-04-01' }),
    tx({ account: 'usd', ledgerId: 'family',   amount: 5000, date: '2026-04-02' }), // wrong ledger, skipped
  ];
  // Cost basis: 1000 (opening) + 200 (personal txn) = 1200. Value: 1000 * 1.35 = 1350.
  // Unrealized FX = 1350 − 1200 = 150. (Without the ledger filter we'd see −5450.)
  expect(unrealizedFx(a, txns, sgdToBase)).toBe(150);
});

const holding = (over: Partial<Holding>): Holding => ({
  id: 'h1',
  ledgerId: 'personal',
  accountId: 'inv',
  symbol: 'VTI',
  name: null,
  shares: 10,
  costBasis: 2000,
  currency: 'USD',
  lastPrice: null,
  lastPriceDate: null,
  notes: null,
  ...over,
});

test('holdingValue: null when no last price is logged', () => {
  expect(holdingValue(holding({ lastPrice: null }))).toBeNull();
});

test('holdingValue: shares × last price', () => {
  expect(holdingValue(holding({ shares: 10, lastPrice: 250 }))).toBe(2500);
});

test('holdingGainLoss: positive when value exceeds cost basis, null without a price', () => {
  expect(holdingGainLoss(holding({ shares: 10, costBasis: 2000, lastPrice: 250 }))).toBe(500);
  expect(holdingGainLoss(holding({ shares: 10, costBasis: 2000, lastPrice: 150 }))).toBe(-500);
  expect(holdingGainLoss(holding({ lastPrice: null }))).toBeNull();
});

test('holdingsValueForAccount: sums live values; falls back to cost basis when no price', () => {
  const hs = [
    holding({ id: 'a', shares: 10, lastPrice: 250, costBasis: 2000 }), // value 2500
    holding({ id: 'b', shares: 5, lastPrice: null, costBasis: 500 }),  // falls back to 500
    holding({ id: 'c', accountId: 'other', shares: 99, lastPrice: 99 }), // not counted
  ];
  expect(holdingsValueForAccount(hs, 'inv')).toBe(3000);
});

test('holdingsForAccount: filters by accountId', () => {
  const hs = [
    holding({ id: 'a', accountId: 'inv' }),
    holding({ id: 'b', accountId: 'inv' }),
    holding({ id: 'c', accountId: 'other' }),
  ];
  expect(holdingsForAccount(hs, 'inv').map((h) => h.id)).toEqual(['a', 'b']);
});

test('investmentAccountTotal: investment → cash + holdings; non-investment → balance unchanged', () => {
  const inv = acct({ id: 'inv', type: 'investment', balance: 500 });
  const hs = [holding({ accountId: 'inv', shares: 10, lastPrice: 250 })]; // value 2500
  expect(investmentAccountTotal(inv, hs)).toBe(3000);

  const cash = acct({ id: 'cash', type: 'savings', balance: 500 });
  // Holdings on an unrelated account aren't dragged in.
  expect(investmentAccountTotal(cash, hs)).toBe(500);
});

// ---------------------------------------------------------------------------
// suggestCategory — local-heuristic next-category guess for a new expense.
// ---------------------------------------------------------------------------

test('suggestCategory: empty description + no counterparty → null', () => {
  expect(suggestCategory([], 'personal', '')).toBeNull();
  expect(suggestCategory([], 'personal', '   ')).toBeNull();
});

test('suggestCategory: matches case-insensitive description', () => {
  const txns = [
    tx({ merchant: 'Blue Bottle', category: 'food', amount: -10 }),
    tx({ merchant: 'BLUE BOTTLE', category: 'food', amount: -8 }),
    tx({ merchant: 'Other', category: 'utils', amount: -50 }),
  ];
  const s = suggestCategory(txns, 'personal', 'blue bottle');
  expect(s).not.toBeNull();
  expect(s!.categoryId).toBe('food');
  expect(s!.count).toBe(2);
  expect(s!.confidence).toBe(1);
});

test('suggestCategory: counterparty match takes priority over description', () => {
  const txns = [
    tx({ merchant: 'Old name', category: 'food', amount: -10, counterpartyId: 'cp-1' }),
    tx({ merchant: 'Another', category: 'food', amount: -10, counterpartyId: 'cp-1' }),
    // Same description as the query but wrong counterparty — must be ignored.
    tx({ merchant: 'Whole Foods', category: 'utils', amount: -10, counterpartyId: 'cp-2' }),
  ];
  const s = suggestCategory(txns, 'personal', 'Whole Foods', 'cp-1');
  expect(s).not.toBeNull();
  expect(s!.categoryId).toBe('food');
  expect(s!.count).toBe(2);
});

test('suggestCategory: ignores pending, refunds, transfers, income, and other ledgers', () => {
  const txns = [
    tx({ merchant: 'Test', category: 'food', amount: -10, pending: true }),
    tx({ merchant: 'Test', category: 'food', amount: 10, kind: 'refund' }),
    tx({ merchant: 'Test', category: 'food', amount: -10, kind: 'transfer' }),
    tx({ merchant: 'Test', category: 'food', amount: 10, kind: 'income' }),
    tx({ merchant: 'Test', category: 'food', amount: -10, ledgerId: 'family' }),
    // Only this one should count.
    tx({ merchant: 'Test', category: 'utils', amount: -10 }),
  ];
  const s = suggestCategory(txns, 'personal', 'Test');
  expect(s).not.toBeNull();
  expect(s!.categoryId).toBe('utils');
  expect(s!.count).toBe(1);
});

test('suggestCategory: returns the dominant category when history is mixed', () => {
  const txns = [
    tx({ merchant: 'Amazon', category: 'food', amount: -10 }),
    tx({ merchant: 'Amazon', category: 'food', amount: -10 }),
    tx({ merchant: 'Amazon', category: 'food', amount: -10 }),
    tx({ merchant: 'Amazon', category: 'office', amount: -10 }),
  ];
  const s = suggestCategory(txns, 'personal', 'Amazon');
  expect(s!.categoryId).toBe('food');
  expect(s!.count).toBe(3);
  expect(s!.confidence).toBeCloseTo(0.75, 2);
});

test('suggestCategory: splits override the parent category for the count', () => {
  // A past row split 50/50 between food and utils. Both should count once.
  const txns = [
    tx({
      merchant: 'Costco', category: 'household', amount: -100,
      splits: [
        { id: 's1', categoryId: 'food', amount: -50, amountBase: -50, description: null },
        { id: 's2', categoryId: 'utils', amount: -50, amountBase: -50, description: null },
      ],
    }),
    tx({ merchant: 'Costco', category: 'food', amount: -20 }),
  ];
  const s = suggestCategory(txns, 'personal', 'Costco');
  expect(s).not.toBeNull();
  // After the split row contributes one food + one utils, plus the plain food
  // row: food=2, utils=1 — food wins.
  expect(s!.categoryId).toBe('food');
  expect(s!.count).toBe(2);
});

test('suggestCategory: returns null when nothing matches', () => {
  const txns = [tx({ merchant: 'Other', category: 'food', amount: -10 })];
  expect(suggestCategory(txns, 'personal', 'Nowhere')).toBeNull();
});
