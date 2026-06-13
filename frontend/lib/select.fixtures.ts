// frontend/lib/select.fixtures.ts — the deterministic parity oracle.
//
// Single source of truth for the Phase-1.0 selector parity fixtures. Consumed by
// `scripts/export-fixtures.ts`, which computes each case's `expected` by running
// the REAL web selector on `input` — so every emitted fixture is correct-by-
// construction against the web oracle, and the Swift port must reproduce it.
// (Phase 1.5 will also iterate CASES from lib/select.test.ts.)
//
// FIXED ids only — NO Math.random() — so the fixtures are deterministic.
import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/domain/accounts/types';
import type { BudgetRow } from '@/lib/db/domain/budgets/types';

/** The Phase-1.0 selectors (see _CANONICAL_WEB_FACTS.md §E) + the Phase-1.5
 *  selectors as they are ported batch-by-batch. */
export type SelectorName =
  | 'accountBalance' | 'selectTransactions' | 'categorySpend'
  | 'budgetProgress' | 'cycleWindow' | 'merchantStats' | 'anomalyScore'
  // Phase 1.5 — batch 1 (time series / deltas)
  | 'currentMonth' | 'prevMonth' | 'monthlySpending' | 'dailySpending'
  | 'monthlyCashflow' | 'topCategoryDeltas'
  // Phase 1.5 — batch 2 (aggregates / digest)
  | 'incomeCategoryFlow' | 'recentExpenses' | 'findDuplicate'
  | 'suggestCategory' | 'weeklyDigest'
  // Phase 1.5 — batch 3a (account / net worth)
  | 'netWorthByMonth' | 'netWorthExplained' | 'balanceSeries'
  | 'netWorthSeries' | 'netWorthByAccountType' | 'selectTransfers';

/** One parity case. `input` is a NAMED-OBJECT (the selector's named args, per
 *  _CANONICAL_WEB_FACTS.md §E) — NOT a positional array. `expected` is NOT stored
 *  here: `scripts/export-fixtures.ts` computes it by running the real selector. */
export interface SelectorCase {
  /** Stable case slug, e.g. "under-budget" — used in the output filename. */
  name: string;
  selector: SelectorName;
  input: Record<string, unknown>;
}

// ---- deterministic builders (fixed ids; mirror lib/select.test.ts shapes) ----
const txOf = (over: Partial<Tx>): Tx => ({
  id: 'tx', merchant: 'm', category: 'food', amount: -10, account: 'a1',
  date: '2026-05-01', pending: false, ledgerId: 'personal', ...over,
});
const acctOf = (over: Partial<AccountRow>): AccountRow => ({
  id: 'a1', ledgerId: 'personal', name: 'Checking', type: 'cash',
  currency: 'USD', balance: 0, openingBalance: 0, openingBalanceBase: 0,
  groupId: null, groupName: null, includeInNetWorth: 1, isActive: true,
  color: null, sortOrder: 0, lastReconciledAt: null,
  lastReconciledBalance: null, archivedAt: null, ...over,
});
const budgetOf = (over: Partial<BudgetRow>): BudgetRow => ({
  id: 'b1', ledgerId: 'personal', groupId: null, name: 'Food',
  type: 'expense' as BudgetRow['type'], amount: 500, saved: 0, carryForward: 0,
  frequency: 'monthly', startDate: '2026-01-01', endDate: null, isRecurring: 1,
  rollover: 0, rolloverLimit: null, pendingAmount: null, lastRolledPeriod: null,
  accountIds: [], categoryIds: ['food'], warningPct: 80, ...over,
});

export const CASES: SelectorCase[] = [
  // ── accountBalance(accounts, accountId) ──
  { name: 'present', selector: 'accountBalance',
    input: { accounts: [acctOf({ id: 'a1', balance: 1234.56 }), acctOf({ id: 'a2', balance: 9 })], accountId: 'a1' } },
  { name: 'missing', selector: 'accountBalance',
    input: { accounts: [acctOf({ id: 'a1', balance: 100 })], accountId: 'zzz' } },

  // ── categorySpend(txns, ledgerId, month?) ──
  { name: 'sums-by-category', selector: 'categorySpend',
    input: { txns: [
      txOf({ id: 't1', category: 'food', amount: -10 }),
      txOf({ id: 't2', category: 'food', amount: -25 }),
      txOf({ id: 't3', category: 'transport', amount: -8 }),
      txOf({ id: 't4', category: 'food', amount: 50 }), // income — excluded
    ], ledgerId: 'personal' } },
  { name: 'empty', selector: 'categorySpend', input: { txns: [], ledgerId: 'personal' } },

  // ── cycleWindow(frequency, startDate, today, endDate?, isRecurring?) — UNTESTED on web ──
  { name: 'monthly-recurring', selector: 'cycleWindow',
    input: { frequency: 'monthly', startDate: '2026-01-01', today: '2026-05-15', isRecurring: 1 } },
  { name: 'weekly-recurring', selector: 'cycleWindow',
    input: { frequency: 'weekly', startDate: '2026-01-01', today: '2026-05-15', isRecurring: 1 } },
  { name: 'non-recurring', selector: 'cycleWindow',
    input: { frequency: 'monthly', startDate: '2026-05-01', today: '2026-05-15', endDate: '2026-05-31', isRecurring: 0 } },

  // ── budgetProgress(budget, txns, today, categories?) — UNTESTED on web ──
  { name: 'under-budget', selector: 'budgetProgress',
    input: { budget: budgetOf({ amount: 500, categoryIds: ['food'] }),
      txns: [txOf({ id: 't1', category: 'food', amount: -120, date: '2026-05-03' }),
             txOf({ id: 't2', category: 'food', amount: -80, date: '2026-05-10' })],
      today: '2026-05-15', categories: [{ id: 'food', parentId: null }] } },
  { name: 'over-budget', selector: 'budgetProgress',
    input: { budget: budgetOf({ amount: 100, categoryIds: ['food'] }),
      txns: [txOf({ id: 't1', category: 'food', amount: -150, date: '2026-05-03' })],
      today: '2026-05-15', categories: [{ id: 'food', parentId: null }] } },

  // ── selectTransactions(txns, opts) ──
  { name: 'direction-out', selector: 'selectTransactions',
    input: { txns: [txOf({ id: 't1', amount: -10 }), txOf({ id: 't2', amount: 50 })],
      opts: { ledgerId: 'personal', direction: 'out' } } },
  { name: 'by-account', selector: 'selectTransactions',
    input: { txns: [txOf({ id: 't1', account: 'a1' }), txOf({ id: 't2', account: 'a2' })],
      opts: { ledgerId: 'personal', accountId: 'a1' } } },

  // ── merchantStats(txns, ledgerId) → Map<string, MerchantStats> ──
  { name: 'two-merchants', selector: 'merchantStats',
    input: { txns: [
      txOf({ id: 't1', merchant: 'Coffee', amount: -4 }),
      txOf({ id: 't2', merchant: 'Coffee', amount: -5 }),
      txOf({ id: 't3', merchant: 'Coffee', amount: -6 }),
      txOf({ id: 't4', merchant: 'Gas', amount: -40 }),
    ], ledgerId: 'personal' } },

  // ── anomalyScore(tx, stats, opts?) — `stats` authored as a plain object; the
  //    generator rebuilds it into a Map<string, MerchantStats> before calling. ──
  // `stats` keys are the selector's merchant key = `m:<lowercased merchant>`
  // (verified against the merchantStats fixture output).
  { name: 'is-anomaly', selector: 'anomalyScore',
    input: { tx: txOf({ id: 't1', merchant: 'Coffee', amount: -40 }),
      stats: { 'm:coffee': { count: 5, mean: 4, std: 0.5 } } } },
  { name: 'not-anomaly', selector: 'anomalyScore',
    input: { tx: txOf({ id: 't1', merchant: 'Coffee', amount: -5 }),
      stats: { 'm:coffee': { count: 5, mean: 4, std: 0.5 } } } },

  // ════════════ Phase 1.5 — batch 1: time series / deltas ════════════

  // ── currentMonth(txns, ledgerId?) → "YYYY-MM" (latest tx month) ──
  { name: 'latest-month', selector: 'currentMonth',
    input: { txns: [txOf({ id: 't1', date: '2026-04-10' }), txOf({ id: 't2', date: '2026-05-20' })],
      ledgerId: 'personal' } },

  // ── prevMonth(month) → "YYYY-MM" (incl. year rollover) ──
  { name: 'mid-year', selector: 'prevMonth', input: { month: '2026-03' } },
  { name: 'year-rollover', selector: 'prevMonth', input: { month: '2026-01' } },

  // ── monthlySpending(txns, ledgerId, endMonth, n) → [{m,v}] (oldest first) ──
  { name: 'three-months', selector: 'monthlySpending',
    input: { txns: [
      txOf({ id: 't1', category: 'food', amount: -10, date: '2026-03-05' }),
      txOf({ id: 't2', category: 'food', amount: -25, date: '2026-04-10' }),
      txOf({ id: 't3', category: 'transport', amount: -8, date: '2026-05-15' }),
      txOf({ id: 't4', category: 'food', amount: 50, date: '2026-05-01' }),  // income — excluded
    ], ledgerId: 'personal', endMonth: '2026-05', n: 3 } },

  // ── dailySpending(txns, ledgerId, endDate, n) → [{date,value}] (oldest first) ──
  { name: 'three-days', selector: 'dailySpending',
    input: { txns: [
      txOf({ id: 't1', amount: -10, date: '2026-05-01' }),
      txOf({ id: 't2', amount: -5, date: '2026-05-03' }),
      txOf({ id: 't3', amount: -7, date: '2026-05-03' }),
    ], ledgerId: 'personal', endDate: '2026-05-03', n: 3 } },

  // ── monthlyCashflow(txns, ledgerId, endMonth, n) → [{m,inc,exp}] ──
  { name: 'two-months', selector: 'monthlyCashflow',
    input: { txns: [
      txOf({ id: 't1', amount: 200, date: '2026-04-01' }),   // income
      txOf({ id: 't2', amount: -30, date: '2026-04-12' }),   // expense
      txOf({ id: 't3', amount: -45, date: '2026-05-08' }),   // expense
    ], ledgerId: 'personal', endMonth: '2026-05', n: 2 } },

  // ── topCategoryDeltas(txns, ledgerId, curMonth, categories, count) → [{name,a,b,d}] ──
  // Distinct abs-deltas (transport 50, food 20) so the ordering is unambiguous.
  { name: 'mom-deltas', selector: 'topCategoryDeltas',
    input: { txns: [
      txOf({ id: 't1', category: 'food', amount: -100, date: '2026-04-10' }),
      txOf({ id: 't2', category: 'food', amount: -120, date: '2026-05-10' }),
      txOf({ id: 't3', category: 'transport', amount: -50, date: '2026-05-12' }),
    ], ledgerId: 'personal', curMonth: '2026-05',
      categories: [{ id: 'food', name: 'Food' }, { id: 'transport', name: 'Transport' }], count: 5 } },

  // ════════════ Phase 1.5 — batch 2: aggregates / digest ════════════

  // ── incomeCategoryFlow(txns, categories, ledgerId, month, topN?) → IncomeFlow ──
  { name: 'income-vs-spend', selector: 'incomeCategoryFlow',
    input: { txns: [
      txOf({ id: 't1', amount: 500, date: '2026-05-01' }),                       // income
      txOf({ id: 't2', category: 'food', amount: -100, date: '2026-05-05' }),
      txOf({ id: 't3', category: 'transport', amount: -60, date: '2026-05-10' }),
    ], categories: [{ id: 'food', name: 'Food', color: '#ff0000' },
                    { id: 'transport', name: 'Transport', color: '#00ff00' }],
      ledgerId: 'personal', month: '2026-05', topN: 6 } },

  // ── recentExpenses(txns, ledgerId, limit?) → [RecentExpense] (most-recent first) ──
  { name: 'dedup-recent', selector: 'recentExpenses',
    input: { txns: [
      txOf({ id: 't1', merchant: 'Coffee', category: 'food', amount: -10, account: 'a1', date: '2026-05-03', time: '08:00' }),
      txOf({ id: 't2', merchant: 'Gas', category: 'transport', amount: -20, account: 'a1', date: '2026-05-05', time: '12:00' }),
    ], ledgerId: 'personal', limit: 5 } },

  // ── findDuplicate(txns, ledgerId, draft) → DuplicateMatch | null ──
  { name: 'near-match', selector: 'findDuplicate',
    input: { txns: [txOf({ id: 'tdup', merchant: 'Coffee', amount: -4.5, account: 'a1', date: '2026-05-09' })],
      ledgerId: 'personal',
      draft: { merchant: 'Coffee', amount: -4.5, accountId: 'a1', date: '2026-05-10' } } },
  { name: 'no-match', selector: 'findDuplicate',
    input: { txns: [txOf({ id: 'tx1', merchant: 'Coffee', amount: -4.5, account: 'a1', date: '2026-05-09' })],
      ledgerId: 'personal',
      draft: { merchant: 'Zzz', amount: -9.9, accountId: 'a1', date: '2026-05-10' } } },

  // ── suggestCategory(txns, ledgerId, description, counterpartyId?, opts?) → CategorySuggestion | null ──
  { name: 'by-merchant', selector: 'suggestCategory',
    input: { txns: [
      txOf({ id: 't1', merchant: 'Coffee', category: 'food', amount: -4 }),
      txOf({ id: 't2', merchant: 'Coffee', category: 'food', amount: -5 }),
    ], ledgerId: 'personal', description: 'Coffee' } },

  // ── weeklyDigest(txns, ledgerId, anchor) → WeeklyDigest | null ──
  // anchor 2026-05-18 is a Monday → reported week is Mon 05-11 … Sun 05-17.
  // Distinct this-week category totals (shopping 80 > food 50 > transport 30).
  { name: 'full-recap', selector: 'weeklyDigest',
    input: { txns: [
      txOf({ id: 'w1', category: 'food', amount: -50, date: '2026-05-12' }),       // this week
      txOf({ id: 'w2', category: 'transport', amount: -30, date: '2026-05-13' }),   // this week
      txOf({ id: 'w3', amount: 200, date: '2026-05-14' }),                          // this week income
      txOf({ id: 'w4', category: 'shopping', amount: -80, date: '2026-05-15' }),    // this week (biggest)
      txOf({ id: 'p1', category: 'food', amount: -100, date: '2026-05-06' }),       // prev week
      txOf({ id: 'a1', category: 'food', amount: -60, date: '2026-03-10' }),        // avg window
    ], ledgerId: 'personal', anchor: '2026-05-18' } },

  // ════════════ Phase 1.5 — batch 3a: account / net worth ════════════

  // ── netWorthByMonth(txns, accounts, ledgerId, endMonth, n) → [{m,v}] ──
  { name: 'three-months', selector: 'netWorthByMonth',
    input: { txns: [
      txOf({ id: 't1', amount: -100, date: '2026-04-15' }),
      txOf({ id: 't2', amount: -50, date: '2026-05-10' }),
    ], accounts: [acctOf({ id: 'a1', balance: 1000 })],
      ledgerId: 'personal', endMonth: '2026-05', n: 3 } },

  // ── netWorthExplained(txns, accounts, ledgerId, endMonth, n) → [{m,income,expense,adjustment,fx,net}] ──
  { name: 'income-expense-refund', selector: 'netWorthExplained',
    input: { txns: [
      txOf({ id: 't1', kind: 'income', amount: 500, date: '2026-04-05' }),
      txOf({ id: 't2', kind: 'expense', amount: -100, date: '2026-04-10' }),
      txOf({ id: 't3', kind: 'expense', amount: -50, date: '2026-05-08' }),
      txOf({ id: 't4', kind: 'refund', amount: 20, date: '2026-05-12' }),
    ], accounts: [acctOf({ id: 'a1', balance: 1000 })],
      ledgerId: 'personal', endMonth: '2026-05', n: 2 } },

  // ── balanceSeries(txns, accountId, currentBalance) → [number] ──
  { name: 'two-txns', selector: 'balanceSeries',
    input: { txns: [
      txOf({ id: 't1', account: 'a1', amount: -10, date: '2026-05-01' }),
      txOf({ id: 't2', account: 'a1', amount: -20, date: '2026-05-03' }),
    ], accountId: 'a1', currentBalance: 100 } },

  // ── netWorthSeries(txns, accounts, ledgerId) → [number] ──
  { name: 'series', selector: 'netWorthSeries',
    input: { txns: [
      txOf({ id: 't1', amount: -100, date: '2026-04-15' }),
      txOf({ id: 't2', amount: -50, date: '2026-05-10' }),
    ], accounts: [acctOf({ id: 'a1', balance: 1000 })], ledgerId: 'personal' } },

  // ── netWorthByAccountType(accounts, ledgerId) → [{type,balance}] (6 canonical types) ──
  { name: 'by-type', selector: 'netWorthByAccountType',
    input: { accounts: [
      acctOf({ id: 'a1', type: 'cash', balance: 1000 }),
      acctOf({ id: 'a2', type: 'savings', balance: 500 }),
      acctOf({ id: 'a3', type: 'credit_card', balance: -200 }),
    ], ledgerId: 'personal' } },

  // ── selectTransfers(txns, accounts, ledgerId) → [Transfer] ──
  { name: 'one-transfer', selector: 'selectTransfers',
    input: { txns: [
      txOf({ id: 'tout', account: 'a1', amount: -100, date: '2026-05-10', transferGroupId: 'tg1' }),
      txOf({ id: 'tin', account: 'a2', amount: 100, date: '2026-05-10', transferGroupId: 'tg1' }),
    ], accounts: [acctOf({ id: 'a1', name: 'Checking' }), acctOf({ id: 'a2', name: 'Savings' })],
      ledgerId: 'personal' } },
];
