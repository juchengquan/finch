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

/** The 7 Phase-1.0 selectors (see _CANONICAL_WEB_FACTS.md §E). */
export type SelectorName =
  | 'accountBalance' | 'selectTransactions' | 'categorySpend'
  | 'budgetProgress' | 'cycleWindow' | 'merchantStats' | 'anomalyScore';

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
];
