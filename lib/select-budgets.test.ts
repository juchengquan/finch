import { test, expect } from 'bun:test';
import { cycleWindow, budgetProgress } from '@/lib/select';
import type { Tx } from '@/lib/store';
import type { BudgetRow } from '@/lib/db/queries/budgets';

const tx = (p: Partial<Tx> & { amount: number; date: string }): Tx => ({
  id: Math.random().toString(36).slice(2),
  merchant: 'M',
  category: null,
  account: 'chk',
  ledgerId: 'personal',
  ...p,
});

const budget = (p: Partial<BudgetRow>): BudgetRow => ({
  id: 'bgt-1',
  ledgerId: 'personal',
  groupId: null,
  name: 'B',
  type: 'expense',
  amount: 500,
  saved: 0,
  carryForward: 0,
  frequency: 'monthly',
  startDate: '2026-05-01',
  endDate: null,
  isRecurring: 1,
  rollover: 0,
  rolloverLimit: null,
  pendingAmount: null,
  lastRolledPeriod: null,
  accountIds: [],
  categoryIds: [],
  warningPct: 80,
  ...p,
});

test('cycleWindow monthly anchors on the start day-of-month', () => {
  expect(cycleWindow('monthly', '2026-01-15', '2026-05-20')).toEqual({ from: '2026-05-15', to: '2026-06-14' });
});

test('cycleWindow weekly steps in 7-day periods from the start', () => {
  expect(cycleWindow('weekly', '2026-05-01', '2026-05-20')).toEqual({ from: '2026-05-15', to: '2026-05-21' });
});

test('cycleWindow daily is a single day', () => {
  expect(cycleWindow('daily', '2026-05-01', '2026-05-20')).toEqual({ from: '2026-05-20', to: '2026-05-20' });
});

test('cycleWindow clamps day across short months (Jan 31 → Feb)', () => {
  // Anchor is the 31st; the next occurrence clamps to Feb 28, so Feb 15 still
  // sits in the period that started Jan 31 and ends the day before (Feb 27).
  expect(cycleWindow('monthly', '2026-01-31', '2026-02-15')).toEqual({ from: '2026-01-31', to: '2026-02-27' });
});

test('cycleWindow non-recurring spans start..end', () => {
  expect(cycleWindow('monthly', '2026-01-15', '2026-05-20', '2026-12-31', 0)).toEqual({
    from: '2026-01-15',
    to: '2026-12-31',
  });
});

test('cycleWindow before the start date clamps to the first period', () => {
  expect(cycleWindow('monthly', '2026-06-01', '2026-05-20')).toEqual({ from: '2026-06-01', to: '2026-06-30' });
});

test('budgetProgress (expense) sums matching outflows in the window', () => {
  const b = budget({ categoryIds: ['food'], amount: 500 });
  const txns: Tx[] = [
    tx({ amount: -100, date: '2026-05-10', category: 'food' }),
    tx({ amount: -50, date: '2026-05-18', category: 'food' }),
    tx({ amount: -30, date: '2026-05-12', category: 'transport' }), // wrong category
    tx({ amount: 20, date: '2026-05-12', category: 'food' }), // inflow ignored for expense
    tx({ amount: -40, date: '2026-04-30', category: 'food' }), // before window
    tx({ amount: -200, date: '2026-05-15', category: 'food', pending: true }), // pending excluded
  ];
  const p = budgetProgress(b, txns, '2026-05-20');
  expect(p.from).toBe('2026-05-01');
  expect(p.to).toBe('2026-05-31');
  expect(p.used).toBe(150);
  expect(p.base).toBe(500);
  expect(p.remaining).toBe(350);
  expect(p.pct).toBe(30);
  expect(p.over).toBe(false);
});

test('budgetProgress respects the account filter and carry-forward', () => {
  const b = budget({ categoryIds: ['food'], accountIds: ['chk'], amount: 200, carryForward: 50 });
  const txns: Tx[] = [
    tx({ amount: -120, date: '2026-05-10', category: 'food', account: 'chk' }),
    tx({ amount: -300, date: '2026-05-11', category: 'food', account: 'sav' }), // other account
  ];
  const p = budgetProgress(b, txns, '2026-05-20');
  expect(p.used).toBe(120);
  expect(p.base).toBe(250); // 200 + 50 carry
  expect(p.over).toBe(false);
});

test('budgetProgress counts only the matching split portion', () => {
  const b = budget({ categoryIds: ['food'], amount: 500 });
  const txns: Tx[] = [
    tx({
      amount: -100,
      date: '2026-05-10',
      category: null,
      splits: [
        { id: 's1', categoryId: 'food', amount: -60, amountBase: -60, description: null },
        { id: 's2', categoryId: 'fun', amount: -40, amountBase: -40, description: null },
      ],
    }),
  ];
  expect(budgetProgress(b, txns, '2026-05-20').used).toBe(60);
});

test('budgetProgress (recurring income) sums matching inflows', () => {
  const b = budget({ type: 'income', categoryIds: ['salary'], amount: 5000 });
  const txns: Tx[] = [
    tx({ amount: 5000, date: '2026-05-01', category: 'salary' }),
    tx({ amount: -200, date: '2026-05-02', category: 'salary' }), // outflow ignored for income
  ];
  const p = budgetProgress(b, txns, '2026-05-20');
  expect(p.used).toBe(5000);
  expect(p.pct).toBe(100);
});

test('budgetProgress (one-shot income/goal) uses the manual saved accumulator', () => {
  const b = budget({ type: 'income', isRecurring: 0, amount: 30000, saved: 12000, startDate: '2026-01-15' });
  const txns: Tx[] = [tx({ amount: 9999, date: '2026-05-01', category: 'salary' })]; // ignored
  const p = budgetProgress(b, txns, '2026-05-20');
  expect(p.used).toBe(12000);
  expect(p.base).toBe(30000);
  expect(p.pct).toBe(40);
});
