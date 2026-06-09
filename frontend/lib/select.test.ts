import { test, expect } from 'bun:test';
import { balanceSeries, netWorthSeries, categorySpend, monthlySpending, monthlyCashflow, topCategoryDeltas, dailySpending, netWorthByMonth, netWorthByAccountType, netWorthExplained, selectTransactions, monthForecast, incomeCategoryFlow, unrealizedFx, holdingValue, holdingGainLoss, holdingsForAccount, holdingsValueForAccount, investmentAccountTotal, suggestCategory, recentExpenses, findDuplicate, accountForecast, merchantStats, anomalyScore, weeklyDigest } from "@/lib/select";
import type { Holding } from '@/lib/db/domain/holdings/types';
import type { Tx, ScheduledTemplate } from '@/lib/store';
import type { AccountRow } from '@/lib/db/domain/accounts/types';

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
  openingBalance: 0,
  openingBalanceBase: 0,
  groupId: null,
  groupName: null,
  includeInNetWorth: 1,
  isActive: true,
  color: null,
  sortOrder: 0,
  lastReconciledAt: null,
  lastReconciledBalance: null,
  archivedAt: null,
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

test('netWorthSeries excludes accounts with includeInNetWorth=0', () => {
  const accounts: AccountRow[] = [
    { id: 'chk', name: 'Chk', balance: 1000, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1 } as AccountRow,
    { id: 'cc',  name: 'CC',  balance: -500, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 0 } as AccountRow,
  ];
  const series = netWorthSeries([], accounts, 'personal');
  // Last point IS the current total. Without filter: 500; with: 1000.
  expect(series[series.length - 1]).toBe(1000);
});

test('netWorthSeries excludes accounts with isActive=0', () => {
  const accounts: AccountRow[] = [
    { id: 'chk', name: 'Chk', balance: 1000, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'old', name: 'Old', balance: -500, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1, isActive: false } as AccountRow,
  ];
  const series = netWorthSeries([], accounts, 'personal');
  // Last point IS the current total. Without filter: 500; with isActive: 1000.
  expect(series[series.length - 1]).toBe(1000);
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

test('netWorthByMonth excludes accounts with includeInNetWorth=0', () => {
  const accounts: AccountRow[] = [
    { id: 'chk', name: 'Chk', balance: 1000, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1 } as AccountRow,
    { id: 'cc',  name: 'CC',  balance: -500, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 0 } as AccountRow,
  ];
  const series = netWorthByMonth([], accounts, 'personal', '2026-06', 3);
  // Without the filter, total would be 500. With it, only chk counts → 1000.
  expect(series[series.length - 1].v).toBe(1000);
});

test('netWorthByMonth excludes accounts with isActive=0', () => {
  const accounts: AccountRow[] = [
    { id: 'chk', name: 'Chk', balance: 1000, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'old', name: 'Old', balance: -500, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1, isActive: false } as AccountRow,
  ];
  const series = netWorthByMonth([], accounts, 'personal', '2026-06', 3);
  // Without the isActive filter, total would be 500. With it, only chk counts → 1000.
  expect(series[series.length - 1].v).toBe(1000);
});

test('netWorthByAccountType splits a single-currency ledger into all 6 types', () => {
  // One account per type, all active and counted. All in ledger base (USD),
  // so the toBase default is identity — balances pass through unchanged.
  const accounts: AccountRow[] = [
    { id: 'cash',  name: 'Wallet', balance: 100, currency: 'USD', type: 'cash',        ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'sav',   name: 'Sav',    balance: 500, currency: 'USD', type: 'savings',     ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'inv',   name: 'Inv',    balance: 800, currency: 'USD', type: 'investment',  ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'cc',    name: 'CC',     balance: -200,currency: 'USD', type: 'credit_card', ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'fx',    name: 'FX',     balance: 50,  currency: 'USD', type: 'fx',          ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'virt',  name: 'Virt',   balance: 0,   currency: 'USD', type: 'virtual',     ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
  ];
  const out = netWorthByAccountType(accounts, 'personal');
  // Always 6 buckets in canonical order, even when zero.
  expect(out.map((b) => b.type)).toEqual(['cash', 'savings', 'investment', 'credit_card', 'fx', 'virtual']);
  expect(out.find((b) => b.type === 'cash')!.balance).toBe(100);
  expect(out.find((b) => b.type === 'savings')!.balance).toBe(500);
  expect(out.find((b) => b.type === 'investment')!.balance).toBe(800);
  expect(out.find((b) => b.type === 'credit_card')!.balance).toBe(-200);
  expect(out.find((b) => b.type === 'fx')!.balance).toBe(50);
  expect(out.find((b) => b.type === 'virtual')!.balance).toBe(0);
});

test('netWorthByAccountType honours includeInNetWorth=0 and isActive=0', () => {
  // One counted account (cash) and four excluded accounts (one per exclusion
  // vector per relevant type) — verifies the bucket for each excluded type
  // is zero, not the account's balance.
  const accounts: AccountRow[] = [
    { id: 'cash',  name: 'Wallet', balance: 100, currency: 'USD', type: 'cash',        ledgerId: 'personal', includeInNetWorth: 1, isActive: true } as AccountRow,
    { id: 'sav',   name: 'Sav',    balance: 999, currency: 'USD', type: 'savings',     ledgerId: 'personal', includeInNetWorth: 0, isActive: true } as AccountRow,
    { id: 'inv',   name: 'Inv',    balance: 999, currency: 'USD', type: 'investment',  ledgerId: 'personal', includeInNetWorth: 1, isActive: false } as AccountRow,
    { id: 'cc',    name: 'CC',     balance: 999, currency: 'USD', type: 'credit_card', ledgerId: 'personal', includeInNetWorth: 0, isActive: false } as AccountRow,
    { id: 'fx',    name: 'FX',     balance: 999, currency: 'USD', type: 'fx',          ledgerId: 'other',    includeInNetWorth: 1, isActive: true } as AccountRow,
  ];
  const out = netWorthByAccountType(accounts, 'personal');
  expect(out.find((b) => b.type === 'cash')!.balance).toBe(100);
  // Excluded types collapse to 0.
  expect(out.find((b) => b.type === 'savings')!.balance).toBe(0);
  expect(out.find((b) => b.type === 'investment')!.balance).toBe(0);
  expect(out.find((b) => b.type === 'credit_card')!.balance).toBe(0);
  // fx account is in a different ledger → excluded.
  expect(out.find((b) => b.type === 'fx')!.balance).toBe(0);
});

test('netWorthExplained buckets a month into income / expense / adjustment / fx', () => {
  // Single-currency ledger so fx is exactly 0 — keeps the assertions tight.
  const accounts: AccountRow[] = [
    { id: 'chk', name: 'Chk', balance: 1500, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1 } as AccountRow,
  ];
  const txns: Tx[] = [
    { id: 't1', amount: 3000, date: '2026-06-05', kind: 'income',     ledgerId: 'personal', account: 'chk', merchant: 'Salary' } as Tx,
    { id: 't2', amount: -100, date: '2026-06-10', kind: 'expense',    ledgerId: 'personal', account: 'chk', merchant: 'Coffee' } as Tx,
    { id: 't3', amount: -50,  date: '2026-06-12', kind: 'adjustment', ledgerId: 'personal', account: 'chk', merchant: 'Reconcile' } as Tx,
  ];
  const series = netWorthExplained(txns, accounts, 'personal', '2026-06', 1);
  expect(series).toHaveLength(1);
  expect(series[0]).toMatchObject({
    m: '2026-06',
    income: 3000,
    expense: 100,    // stored as positive magnitude
    adjustment: -50,
    fx: 0,
    net: 2850,       // income(3000) - expense(100) + adjustment(-50) + fx(0)
  });
});

test('netWorthExplained returns one bucket per month over a window', () => {
  const accounts: AccountRow[] = [
    { id: 'chk', name: 'Chk', balance: 1000, currency: 'USD', ledgerId: 'personal', includeInNetWorth: 1 } as AccountRow,
  ];
  const txns: Tx[] = [
    { id: 't1', amount: 500,  date: '2026-04-01', kind: 'income',  ledgerId: 'personal', account: 'chk', merchant: 'Salary' } as Tx,
    { id: 't2', amount: -200, date: '2026-05-15', kind: 'expense', ledgerId: 'personal', account: 'chk', merchant: 'Bills' } as Tx,
    { id: 't3', amount: 700,  date: '2026-06-01', kind: 'income',  ledgerId: 'personal', account: 'chk', merchant: 'Salary' } as Tx,
  ];
  const series = netWorthExplained(txns, accounts, 'personal', '2026-06', 3);
  expect(series.map((s) => s.m)).toEqual(['2026-04', '2026-05', '2026-06']);
  expect(series[0].income).toBe(500);
  expect(series[1].expense).toBe(200);
  expect(series[2].income).toBe(700);
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

// ---------------------------------------------------------------------------
// recentExpenses — one-tap "redo" chips for the Add screen.
// ---------------------------------------------------------------------------

test('recentExpenses: empty input → empty list', () => {
  expect(recentExpenses([], 'personal')).toEqual([]);
});

test('recentExpenses: most-recent first, capped at `limit`, returns positive amount magnitudes', () => {
  const txns = [
    tx({ merchant: 'Starbucks', amount: -4, date: '2026-05-29', time: '08:00' }),
    tx({ merchant: 'Whole Foods', amount: -42, date: '2026-05-30', time: '12:00' }),
    tx({ merchant: 'Parking', amount: -3, date: '2026-05-30', time: '14:00' }),
  ];
  const out = recentExpenses(txns, 'personal', 5);
  expect(out.map((r) => r.merchant)).toEqual(['Parking', 'Whole Foods', 'Starbucks']);
  expect(out.every((r) => r.amount > 0)).toBe(true); // chip displays magnitude
});

test('recentExpenses: deduplicates by merchant + amount + account + category', () => {
  const txns = [
    tx({ merchant: 'Starbucks', amount: -4, account: 'cc', category: 'food', date: '2026-05-29' }),
    tx({ merchant: 'Starbucks', amount: -4, account: 'cc', category: 'food', date: '2026-05-25' }),
    tx({ merchant: 'Starbucks', amount: -4, account: 'cc', category: 'food', date: '2026-05-20' }),
    // Different amount → counts as a separate chip.
    tx({ merchant: 'Starbucks', amount: -6, account: 'cc', category: 'food', date: '2026-05-26' }),
  ];
  const out = recentExpenses(txns, 'personal');
  expect(out.length).toBe(2);
  expect(out.map((r) => r.amount)).toEqual([4, 6]);
});

test('recentExpenses: ignores pending, refunds, transfers, income, and other ledgers', () => {
  const txns = [
    tx({ merchant: 'Pending', amount: -10, pending: true, date: '2026-05-30' }),
    tx({ merchant: 'Refund', amount: 10, kind: 'refund', date: '2026-05-30' }),
    tx({ merchant: 'Transfer', amount: -10, kind: 'transfer', date: '2026-05-30' }),
    tx({ merchant: 'Salary', amount: 5000, kind: 'income', date: '2026-05-30' }),
    tx({ merchant: 'Other ledger', amount: -10, ledgerId: 'family', date: '2026-05-30' }),
    tx({ merchant: 'Real expense', amount: -10, date: '2026-05-29' }),
  ];
  const out = recentExpenses(txns, 'personal');
  expect(out.map((r) => r.merchant)).toEqual(['Real expense']);
});

test('recentExpenses: respects the limit parameter', () => {
  const txns = Array.from({ length: 10 }, (_, i) =>
    tx({ merchant: `M${i}`, amount: -(i + 1), date: `2026-05-${10 + i}` }),
  );
  expect(recentExpenses(txns, 'personal', 3).length).toBe(3);
});

// ---------------------------------------------------------------------------
// accountForecast — 30/60/90-day cashflow projection.
// ---------------------------------------------------------------------------

const sched = (over: Partial<ScheduledTemplate>): ScheduledTemplate => ({
  id: 't-rent', name: 'Rent', type: 'expense', amount: 1850,
  frequency: 'monthly', dayOfMonth: 1,
  accountId: 'chk', account: 'Chase Checking',
  autoPost: 1, nextRun: '', lastRun: '',
  startDate: '2026-01-01',
  ...over,
});

test('accountForecast: no scheduled templates → flat balance, trough = starting', () => {
  const a = acct({ id: 'chk', balance: 5000, currency: 'USD' });
  const f = accountForecast(a, [], '2026-06-01', 30);
  expect(f.startingBalance).toBe(5000);
  expect(f.endingBalance).toBe(5000);
  expect(f.trough.balance).toBe(5000);
  expect(f.events.length).toBe(0);
  expect(f.series.length).toBe(31); // today + 30 days
});

test('accountForecast: monthly rent debit reduces the balance on the 1st', () => {
  const a = acct({ id: 'chk', balance: 5000, currency: 'USD' });
  // Today is Jun 10; rent on the 1st has already passed for June, next hit
  // is Jul 1 — within the 30-day horizon.
  const f = accountForecast(a, [sched({})], '2026-06-10', 30);
  expect(f.events.length).toBe(1);
  expect(f.events[0].date).toBe('2026-07-01');
  expect(f.events[0].amount).toBe(-1850);
  expect(f.endingBalance).toBe(3150); // 5000 - 1850
  expect(f.trough.balance).toBe(3150);
  expect(f.trough.date).toBe('2026-07-01');
});

test('accountForecast: salary credit + rent debit net out across 60 days', () => {
  const a = acct({ id: 'chk', balance: 1000, currency: 'USD' });
  const templates = [
    sched({ id: 't-rent', name: 'Rent', type: 'expense', amount: 1500, dayOfMonth: 1 }),
    sched({ id: 't-sal',  name: 'Salary', type: 'income',  amount: 3000, dayOfMonth: 15 }),
  ];
  // Today: Jun 10. Horizon 60d → through Aug 9. Events:
  //   Jun 15 +3000  → 4000
  //   Jul 1  −1500  → 2500
  //   Jul 15 +3000  → 5500
  //   Aug 1  −1500  → 4000
  const f = accountForecast(a, templates, '2026-06-10', 60);
  expect(f.events.length).toBe(4);
  expect(f.endingBalance).toBe(4000);
});

test('accountForecast: transfer leg signs apply correctly (from = −, to = +)', () => {
  const chk = acct({ id: 'chk', balance: 2000, currency: 'USD' });
  const sav = acct({ id: 'sav', balance: 500, currency: 'USD' });
  const sweep = sched({
    id: 't-sweep', name: 'Weekly sweep', type: 'transfer',
    amount: 100, frequency: 'weekly',
    accountId: 'sav', account: 'Savings',
    fromAccountId: 'chk', from: 'Checking',
    weekDay: 1, // Mondays
    startDate: '2026-06-01',
  });
  const chkForecast = accountForecast(chk, [sweep], '2026-06-01', 30);
  const savForecast = accountForecast(sav, [sweep], '2026-06-01', 30);
  // Same template, opposite signs on the two accounts.
  expect(chkForecast.events.every((e) => e.amount === -100)).toBe(true);
  expect(savForecast.events.every((e) => e.amount === 100)).toBe(true);
  // Same number of events on both sides (the two legs of each occurrence).
  expect(chkForecast.events.length).toBe(savForecast.events.length);
});

test('accountForecast: trough tracks the lowest balance and its date', () => {
  const a = acct({ id: 'chk', balance: 1000, currency: 'USD' });
  const templates = [
    sched({ id: 't-rent', type: 'expense', amount: 800, dayOfMonth: 5 }),
    sched({ id: 't-sal',  type: 'income',  amount: 500, dayOfMonth: 20 }),
  ];
  // Today: Jun 1. Jun 5 −800 → 200 (trough). Jun 20 +500 → 700. Jul 5 −800 → −100 (new trough).
  const f = accountForecast(a, templates, '2026-06-01', 60);
  expect(f.trough.date).toBe('2026-07-05');
  expect(f.trough.balance).toBe(-100);
});

test('accountForecast: installment_total caps future occurrences', () => {
  const a = acct({ id: 'chk', balance: 2400, currency: 'USD' });
  // 12-month plan; 8 already paid → only 4 future occurrences should fire.
  const plan = sched({
    id: 't-plan', name: 'Phone plan', type: 'expense', amount: 50,
    dayOfMonth: 1, installmentTotal: 12, installmentPaid: 8,
    startDate: '2026-01-01',
  });
  const f = accountForecast(a, [plan], '2026-06-10', 365);
  expect(f.events.length).toBe(4);
});

// ---------------------------------------------------------------------------
// merchantStats + anomalyScore — per-merchant z-score for the "Unusual" badge.
// ---------------------------------------------------------------------------

test('merchantStats: counts only confirmed expenses, groups by counterparty FK first', () => {
  const txns = [
    tx({ merchant: 'Old name', amount: -10, counterpartyId: 'cp-1' }),
    tx({ merchant: 'Renamed', amount: -12, counterpartyId: 'cp-1' }),
    tx({ merchant: 'Refund', amount: 10, kind: 'refund' }),
    tx({ merchant: 'Pending', amount: -10, pending: true }),
    tx({ merchant: 'Transfer', amount: -10, kind: 'transfer' }),
    tx({ merchant: 'Income', amount: 100, kind: 'income' }),
    tx({ merchant: 'OtherLedger', amount: -10, ledgerId: 'family' }),
  ];
  const stats = merchantStats(txns, 'personal');
  // Both expense rows share the FK; the wrong-kind/pending/other-ledger rows
  // are filtered out.
  expect(stats.get('cp:cp-1')?.count).toBe(2);
  expect(stats.get('cp:cp-1')?.mean).toBe(11);
  expect(stats.size).toBe(1);
});

test('merchantStats: falls back to lowercased description when no counterparty FK', () => {
  const txns = [
    tx({ merchant: 'BLUE BOTTLE', amount: -8 }),
    tx({ merchant: 'blue bottle', amount: -10 }),
    tx({ merchant: 'Blue Bottle', amount: -12 }),
  ];
  const stats = merchantStats(txns, 'personal');
  expect(stats.get('m:blue bottle')?.count).toBe(3);
  expect(stats.get('m:blue bottle')?.mean).toBe(10);
});

test('anomalyScore: returns null without enough history (n < 2)', () => {
  const txns = [tx({ merchant: 'New Place', amount: -100 })];
  const stats = merchantStats(txns, 'personal');
  const a = anomalyScore(txns[0], stats);
  expect(a).toBeNull();
});

test('anomalyScore: flags a magnitude well above the merchant mean', () => {
  // Coffee runs are ~$4 (tight cluster). A $40 charge at the same merchant
  // should fire. Stats use history only — the function doc warns about the
  // bias if you include the candidate row in its own aggregation.
  const history = [
    tx({ id: 'h1', merchant: 'Starbucks', amount: -4 }),
    tx({ id: 'h2', merchant: 'Starbucks', amount: -4.5 }),
    tx({ id: 'h3', merchant: 'Starbucks', amount: -3.5 }),
    tx({ id: 'h4', merchant: 'Starbucks', amount: -4 }),
  ];
  const outlier = tx({ id: 'h5', merchant: 'Starbucks', amount: -40 });
  const stats = merchantStats(history, 'personal');
  const a = anomalyScore(outlier, stats);
  expect(a).not.toBeNull();
  expect(a!.isAnomaly).toBe(true);
  expect(a!.count).toBe(4);
  expect(a!.zScore).toBeGreaterThan(2.5);
});

test('anomalyScore: does NOT flag a typical transaction', () => {
  const history = [
    tx({ merchant: 'Starbucks', amount: -4 }),
    tx({ merchant: 'Starbucks', amount: -4.5 }),
    tx({ merchant: 'Starbucks', amount: -3.5 }),
  ];
  const normal = tx({ id: 'n', merchant: 'Starbucks', amount: -4.2 });
  const txns = [...history, normal];
  const stats = merchantStats(txns, 'personal');
  const a = anomalyScore(normal, stats);
  expect(a?.isAnomaly).toBe(false);
});

test('anomalyScore: skips non-expense and pending rows', () => {
  const history = Array.from({ length: 10 }, () => tx({ merchant: 'Test', amount: -10 }));
  const stats = merchantStats(history, 'personal');
  expect(anomalyScore(tx({ merchant: 'Test', amount: 100, kind: 'income' }), stats)).toBeNull();
  expect(anomalyScore(tx({ merchant: 'Test', amount: -100, pending: true }), stats)).toBeNull();
});

// Anchor 2026-05-13 (Wednesday) ⇒ "last week" = 2026-05-04 (Mon) … 2026-05-10 (Sun);
// prev week = 2026-04-27 … 2026-05-03.
test('weeklyDigest: returns null on a ledger with no confirmed history', () => {
  expect(weeklyDigest([], 'personal', '2026-05-13')).toBeNull();
  expect(
    weeklyDigest([tx({ pending: true, date: '2026-05-06', amount: -50 })], 'personal', '2026-05-13'),
  ).toBeNull();
});

test('weeklyDigest: reports the most recently completed Mon-Sun window', () => {
  // Anchor mid-week (Wed) — the digest is "last week", not "this week".
  const txns = [
    tx({ id: 'in-week', date: '2026-05-06', amount: -42, category: 'food' }),
    // Outside the last-week window (still in current week): must NOT count.
    tx({ id: 'this-week', date: '2026-05-13', amount: -99, category: 'food' }),
  ];
  const d = weeklyDigest(txns, 'personal', '2026-05-13');
  expect(d).not.toBeNull();
  expect(d!.weekStart).toBe('2026-05-04');
  expect(d!.weekEnd).toBe('2026-05-10');
  expect(d!.spent).toBe(42);
  expect(d!.txCount).toBe(1);
});

test('weeklyDigest: vs-prev % is signed and rounded; null when there is no prior history', () => {
  // 100 spend last week, 80 prev week → +25%.
  const txns = [
    tx({ id: 'a', date: '2026-05-05', amount: -60, category: 'food' }),
    tx({ id: 'b', date: '2026-05-09', amount: -40, category: 'food' }),
    tx({ id: 'c', date: '2026-04-30', amount: -80, category: 'food' }),
  ];
  const d = weeklyDigest(txns, 'personal', '2026-05-13')!;
  expect(d.spent).toBe(100);
  expect(d.prevSpent).toBe(80);
  expect(d.vsPrevPct).toBe(0.25);

  // No prior week activity at all → vsPrevPct is null (not 0, not Infinity).
  const noPrior = weeklyDigest(
    [tx({ id: 'a', date: '2026-05-05', amount: -60 })],
    'personal',
    '2026-05-13',
  )!;
  expect(noPrior.prevSpent).toBeNull();
  expect(noPrior.vsPrevPct).toBeNull();
});

test('weeklyDigest: top categories sorted desc, capped at 5; biggest hit excludes refunds', () => {
  const mk = (cat: string, amount: number, id = cat) =>
    tx({ id, date: '2026-05-07', amount: -amount, category: cat });
  const txns = [
    mk('a', 60),
    mk('b', 50),
    mk('c', 40),
    mk('d', 30),
    mk('e', 20),
    mk('f', 10),
    // A refund is bigger than any expense, but shouldn't claim the headline.
    tx({ id: 'rf', date: '2026-05-07', amount: 200, category: 'a', kind: 'refund' }),
  ];
  const d = weeklyDigest(txns, 'personal', '2026-05-13')!;
  expect(d.topCategories.map((c) => c.categoryId)).toEqual(['b', 'c', 'd', 'e', 'f']);
  // Category 'a' nets to -140 (60 expense − 200 refund) so falls off; refund offsets correctly.
  expect(d.biggestExpense?.txId).toBe('a');
  expect(d.biggestExpense?.amount).toBe(60);
});

test('weeklyDigest: vsAvgPct null when fewer than 4 weeks of history', () => {
  // Two weeks of trailing data → avgWeeks = 2 → vsAvgPct null.
  const txns = [
    tx({ id: 'w', date: '2026-05-05', amount: -50 }),
    tx({ id: 'p1', date: '2026-04-28', amount: -30 }),
    tx({ id: 'p2', date: '2026-04-21', amount: -30 }),
  ];
  const d = weeklyDigest(txns, 'personal', '2026-05-13')!;
  expect(d.avgWeeks).toBe(2);
  expect(d.vsAvgPct).toBeNull();
});

test('weeklyDigest: income counted from income rows only; net = income - spent', () => {
  const txns = [
    tx({ id: 's', date: '2026-05-05', amount: -100, category: 'food' }),
    tx({ id: 'i', date: '2026-05-07', amount: 300, category: 'salary', kind: 'income' }),
  ];
  const d = weeklyDigest(txns, 'personal', '2026-05-13')!;
  expect(d.spent).toBe(100);
  expect(d.income).toBe(300);
  expect(d.net).toBe(200);
});

test('findDuplicate flags a same-account same-merchant same-amount row within the window', () => {
  const txns = [
    tx({ id: 'a', merchant: 'Starbucks', amount: -6.5, account: 'cc', date: '2026-05-10' }),
  ];
  // Exact match a day later → flagged.
  expect(findDuplicate(txns, 'personal', { merchant: 'starbucks', amount: -6.5, accountId: 'cc', date: '2026-05-11' })?.id).toBe('a');
  // Outside the ±3d window → no match.
  expect(findDuplicate(txns, 'personal', { merchant: 'Starbucks', amount: -6.5, accountId: 'cc', date: '2026-05-20' })).toBeNull();
  // Different account → no match.
  expect(findDuplicate(txns, 'personal', { merchant: 'Starbucks', amount: -6.5, accountId: 'chk', date: '2026-05-10' })).toBeNull();
  // Different amount → no match.
  expect(findDuplicate(txns, 'personal', { merchant: 'Starbucks', amount: -7, accountId: 'cc', date: '2026-05-10' })).toBeNull();
  // The row's own id is excluded (edit case).
  expect(findDuplicate(txns, 'personal', { merchant: 'Starbucks', amount: -6.5, accountId: 'cc', date: '2026-05-10', excludeId: 'a' })).toBeNull();
  // Pending rows are ignored.
  const pend = [tx({ id: 'p', merchant: 'Starbucks', amount: -6.5, account: 'cc', date: '2026-05-10', pending: true })];
  expect(findDuplicate(pend, 'personal', { merchant: 'Starbucks', amount: -6.5, accountId: 'cc', date: '2026-05-10' })).toBeNull();
});
