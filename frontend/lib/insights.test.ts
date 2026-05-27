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
  recurring: false,
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
  groupId: null,
  groupName: null,
  includeInNetWorth: 1,
  ...over,
});

const baseCtx = (over: Partial<InsightCtx>): InsightCtx => ({
  transactions: [],
  categories: [],
  goals: [],
  accounts: [],
  ledgerId: 'personal',
  fmt: (n) => `$${n.toFixed(2)}`,
  ...over,
});

test('empty context yields no insights (caller falls back to curated)', () => {
  expect(generateInsights(baseCtx({}))).toEqual([]);
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
