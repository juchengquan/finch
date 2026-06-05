import { test, expect } from 'bun:test';
import { generateInsights, type InsightCtx } from '@/lib/insights';
import type { Tx } from '@/lib/store';
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
  type: 'cash',
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

const baseCtx = (over: Partial<InsightCtx>): InsightCtx => ({
  transactions: [],
  categories: [],
  goals: [],
  accounts: [],
  ledgerId: 'personal',
  month: '',
  fmt: (n) => `$${n.toFixed(2)}`,
  ...over,
});

test('empty context yields no insights (caller falls back to curated)', () => {
  expect(generateInsights(baseCtx({}))).toEqual([]);
});

test('spending trend compares this month to last', () => {
  const ctx = baseCtx({
    month: '2026-05',
    transactions: [
      tx({ category: 'food', amount: -100, date: '2026-04-10' }), // last month
      tx({ category: 'food', amount: -80, date: '2026-05-10' }), // this month
    ],
    categories: [{ id: 'food', name: 'Food', budget: 1000 }],
  });
  const trend = generateInsights(ctx).find((i) => i.title.includes('vs last month'));
  expect(trend?.title).toBe('Spending down 20% vs last month');
  expect(trend?.tone).toBe('pos');
});

test('over-budget category surfaces as a warning, worst first', () => {
  const ctx = baseCtx({
    transactions: [tx({ category: 'food', amount: -120 }), tx({ category: 'fun', amount: -60 })],
    categories: [
      { id: 'food', name: 'Food', budget: 100 },
      { id: 'fun', name: 'Fun', budget: 50 },
    ],
  });
  const out = generateInsights(ctx);
  const over = out.find((i) => i.title.endsWith('over budget'));
  expect(over?.tone).toBe('warn');
  expect(over?.title).toBe('Food over budget'); // 20 over beats Fun's 10 over
});

test('pending insight reports count and total', () => {
  const ctx = baseCtx({ transactions: [tx({ pending: true, amount: -30 }), tx({ pending: true, amount: -20 })] });
  const p = generateInsights(ctx).find((i) => i.title.includes('pending'));
  expect(p?.title).toBe('2 pending to review');
  expect(p?.body).toContain('$50.00');
});

test('goal progress picks the closest-to-funded goal', () => {
  const ctx = baseCtx({
    goals: [
      { id: 'g1', name: 'Car', target: 1000, saved: 100 },
      { id: 'g2', name: 'Trip', target: 1000, saved: 900 },
    ],
  });
  const g = generateInsights(ctx).find((i) => i.title.includes('funded'));
  expect(g?.title).toBe('Trip is 90% funded');
  expect(g?.tone).toBe('pos');
});

test('net-worth trend reflects direction', () => {
  const ctx = baseCtx({
    accounts: [acct({ id: 'cc', balance: 100 })],
    transactions: [tx({ amount: -40, account: 'cc', date: '2026-05-10' })],
  });
  const nw = generateInsights(ctx).find((i) => i.title.toLowerCase().includes('net worth'));
  // ends at 100, opened at 140 → down over the period.
  expect(nw?.title).toBe('Net worth dipped');
  expect(nw?.tone).toBe('warn');
});

test('caps the number of insights', () => {
  const ctx = baseCtx({
    transactions: [
      tx({ category: 'food', amount: -120, date: '2026-05-01' }),
      tx({ pending: true, amount: -20 }),
    ],
    categories: [{ id: 'food', name: 'Food', budget: 100 }],
    goals: [{ id: 'g1', name: 'Car', target: 1000, saved: 500 }],
    accounts: [acct({ id: 'cc', balance: 100 })],
  });
  expect(generateInsights(ctx, 2).length).toBe(2);
});

// 2026-05-01 is a Friday; 2026-05-02/03 are Sat/Sun. Use it as a basis for
// the day-of-week tests so we don't have to convert mentally per case.
const dayOfWeek = (date: string) => new Date(`${date}T00:00`).getDay();

test('weekendVsWeekday fires when weekend per-day spend ≥ 1.5× weekday', () => {
  // Four full weeks of data (2026-05-01 Fri … 2026-05-28 Thu). Every Sat+Sun
  // gets a $60 row; every Mon–Fri gets a $10 row. Per-day means: 60 vs 10 → 6×.
  const txns: Tx[] = [];
  for (let i = 0; i < 28; i++) {
    const d = new Date('2026-05-01T00:00');
    d.setDate(d.getDate() + i);
    const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    const dow = d.getDay();
    const amt = dow === 0 || dow === 6 ? -60 : -10;
    txns.push(tx({ date: iso, amount: amt, category: 'food' }));
  }
  const out = generateInsights(baseCtx({ transactions: txns }));
  const wk = out.find((i) => i.title.includes('Weekends cost'));
  expect(wk).toBeDefined();
  expect(wk!.body).toContain('×');
});

test('weekendVsWeekday stays silent when weekend/weekday spend is balanced', () => {
  const txns: Tx[] = [];
  for (let i = 0; i < 28; i++) {
    const d = new Date('2026-05-01T00:00');
    d.setDate(d.getDate() + i);
    const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    txns.push(tx({ date: iso, amount: -20, category: 'food' }));
  }
  expect(generateInsights(baseCtx({ transactions: txns })).find((i) => i.title.startsWith('Weekend'))).toBeUndefined();
});

test('topCategoryByWeekday surfaces the dominant category on its weekday', () => {
  // Five Saturdays of $50 dining + one $10 grocery each → dining ≈ 83% of Saturday spend.
  const txns: Tx[] = [];
  for (let w = 0; w < 5; w++) {
    txns.push(tx({ date: `2026-05-0${2 + w * 7 > 9 ? '' : '0'}${2 + w * 7}`.slice(0, 10), amount: -50, category: 'dining' }));
  }
  // Saturdays in May 2026 are 5/2, 5/9, 5/16, 5/23, 5/30.
  const saturdays = ['2026-05-02', '2026-05-09', '2026-05-16', '2026-05-23', '2026-05-30'];
  const rows = saturdays.flatMap((d) => [
    tx({ date: d, amount: -50, category: 'dining' }),
    tx({ date: d, amount: -10, category: 'groceries' }),
  ]);
  // Sanity-check the dates land on Saturday in the test runner's tz.
  expect(saturdays.every((d) => dayOfWeek(d) === 6)).toBe(true);
  const out = generateInsights(
    baseCtx({
      transactions: rows,
      categories: [
        { id: 'dining', name: 'Dining out', budget: 0 },
        { id: 'groceries', name: 'Groceries', budget: 0 },
      ],
    }),
  );
  const card = out.find((i) => i.title.includes('Saturdays are mostly'));
  expect(card?.title).toBe('Saturdays are mostly Dining out');
  expect(card?.body).toMatch(/83%|84%/); // 250/300 = 83.3%
});

test('endOfMonthBump fires when days 23-31 outspend earlier-month days per capita', () => {
  // Three months of history; each month has a single $300 end-of-month rent on
  // the 25th and $30 of food per day on days 1-22. Per-day: end 37.5 vs early
  // 30 isn't enough. Push it: rent moved up to $1000.
  const txns: Tx[] = [];
  for (const m of ['2026-03', '2026-04', '2026-05']) {
    txns.push(tx({ date: `${m}-25`, amount: -1000, category: 'rent' }));
    for (let d = 1; d <= 22; d++) {
      txns.push(tx({ date: `${m}-${String(d).padStart(2, '0')}`, amount: -10, category: 'food' }));
    }
  }
  const out = generateInsights(baseCtx({ transactions: txns }));
  expect(out.find((i) => i.title.includes('End-of-month'))).toBeDefined();
});

test('endOfMonthBump stays silent without ≥ 3 months of history', () => {
  const txns: Tx[] = [
    tx({ date: '2026-05-25', amount: -1000, category: 'rent' }),
    tx({ date: '2026-05-10', amount: -10, category: 'food' }),
  ];
  expect(generateInsights(baseCtx({ transactions: txns })).find((i) => i.title.includes('End-of-month'))).toBeUndefined();
});

test('quietestDay fires when one weekday is reliably below half the daily average', () => {
  // 5 rows on each non-Tuesday weekday, 0 on Tuesday → 30 rows, well above
  // the 25-row floor. Tuesday's total of 0 is the unique min; daily mean is
  // (30 × $10) / 7 ≈ $42.86, so the ratio is 0 < 0.5.
  const samplesByDow: Record<number, string[]> = {
    0: ['2026-05-03', '2026-05-10', '2026-05-17', '2026-05-24', '2026-05-31'], // Sun
    1: ['2026-05-04', '2026-05-11', '2026-05-18', '2026-05-25', '2026-04-27'], // Mon
    3: ['2026-05-06', '2026-05-13', '2026-05-20', '2026-05-27', '2026-04-29'], // Wed
    4: ['2026-05-07', '2026-05-14', '2026-05-21', '2026-05-28', '2026-04-30'], // Thu
    5: ['2026-05-01', '2026-05-08', '2026-05-15', '2026-05-22', '2026-05-29'], // Fri
    6: ['2026-05-02', '2026-05-09', '2026-05-16', '2026-05-23', '2026-05-30'], // Sat
  };
  const txns: Tx[] = [];
  for (const dates of Object.values(samplesByDow))
    for (const d of dates) txns.push(tx({ date: d, amount: -10, category: 'food' }));
  const out = generateInsights(baseCtx({ transactions: txns }));
  const card = out.find((i) => i.title.includes('quietest'));
  expect(card?.title).toBe('Tuesdays are your quietest');
  expect(card?.tone).toBe('pos');
});

test('quietestDay stays silent below 25 expense rows', () => {
  const txns = Array.from({ length: 10 }, () => tx({ date: '2026-05-04', amount: -10 }));
  expect(generateInsights(baseCtx({ transactions: txns })).find((i) => i.title.includes('quietest'))).toBeUndefined();
});
