// frontend/lib/store/initial.ts — the initial state values. Moved from
// lib/store.ts:381-397 (the body of `create<FinanceState>()((set) => ({...}))`).
//
// The initial values are:
// - transactions: SEED_TX (from data/transactions.json)
// - scheduled: SEED_SCHEDULED (from data/scheduled-templates.json)
// - ledgers/accounts/categories/etc.: empty arrays (the server's
//   /api/state replaces them on first StoreHydration)

import transactionsData from '@/data/transactions.json';
import scheduledData from '@/data/scheduled-templates.json';
import type { Tx, ScheduledTemplate } from '@/lib/store';

const SEED_TX = transactionsData as Tx[];
const SEED_SCHEDULED = scheduledData as ScheduledTemplate[];

export const initialState = {
  transactions: SEED_TX,
  scheduled: SEED_SCHEDULED,
  ledgers: [],
  accounts: [],
  accountGroups: [],
  budgets: [],
  budgetGroups: [],
  categories: [],
  counterparties: [],
  exchangeRates: [],
  tags: [],
  holdings: [],
  rules: [],
  attachments: [],
  mobileTabIds: [],
  displayCurrencyByLedger: {},
  backupConfig: { frequencyMs: 60 * 60 * 1000, retention: 14 },
} as const;
