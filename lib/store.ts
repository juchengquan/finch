'use client';

import { create } from 'zustand';
import transactionsData from '@/data/transactions.json';
import pendingData from '@/data/pending.json';
import recurringData from '@/data/recurring-templates.json';

export interface Tx {
  id: string;
  merchant: string;
  category: string | null;
  amount: number;
  account: string;
  date: string;
  time?: string;
  note?: string;
  pending?: boolean;
  recurring?: boolean;
  kind?: string;
  ledgerId?: string;
  transferGroupId?: string;
}

export interface TransferInput {
  fromAccountId: string;
  toAccountId: string;
  amount: number;
  date: string;
  note?: string;
}

export interface PendingItem {
  id: string;
  merchant: string;
  amount: number;
  currency: string;
  date: string;
  account: string;
  reason: string;
  source: string;
}

export interface RecurringSplit {
  account: string;
  pct: number;
  abs: number | null;
  label: string;
}

export interface RecurringTemplate {
  id: string;
  name: string;
  type: string;
  amount: number | null;
  varies?: number;
  frequency: string;
  dayOfMonth: number;
  account: string;
  from?: string;
  autoPost: number;
  nextRun: string;
  lastRun: string;
  splits?: RecurringSplit[];
}

// Editable fields on an otherwise-static MOCK account.
export interface AccountOverride {
  name?: string;
  type?: string;
  last4?: string;
  institution?: string;
  routing?: string;
}

const SEED_TX = transactionsData as Tx[];
const SEED_PENDING = pendingData as PendingItem[];
const SEED_RECURRING = recurringData as RecurringTemplate[];

interface FinanceState {
  transactions: Tx[];
  pending: PendingItem[];
  recurring: RecurringTemplate[];
  // Editable overrides on otherwise-static mock data, persisted.
  budgetOverrides: Record<string, number>;
  accountOverrides: Record<string, AccountOverride>;
  verifiedExtra: string[];
  aliasExtra: Record<string, string[]>;

  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  setBudget: (categoryId: string, amount: number) => void;
  setAccountDetails: (accountId: string, patch: AccountOverride) => void;
  updateRecurringSplit: (templateId: string, index: number, pct: number) => void;
  verifyCounterparty: (id: string) => void;
  addAlias: (id: string, alias: string) => void;
  createTransfer: (input: TransferInput) => void;
  postRecurring: (templateId: string) => void;
  reset: () => void;
}

// The authoritative database lives on the server. Each action updates the store
// optimistically for instant UI, then POSTs the same change to the server and
// replaces the store with the server's projected state (the source of truth).
// StoreHydration seeds the store from the server on load.
function syncMutation(action: string, args?: Record<string, unknown>): void {
  if (typeof window === 'undefined') return;
  void import('@/lib/api-client')
    .then(({ mutate }) => mutate(action, args))
    .then((state) => useFinanceStore.setState(state))
    .catch((err) => console.error(`Sync failed (${action})`, err));
}

export const useFinanceStore = create<FinanceState>()(
  (set) => ({
      transactions: SEED_TX,
      pending: SEED_PENDING,
      recurring: SEED_RECURRING,
      budgetOverrides: {},
      accountOverrides: {},
      verifiedExtra: [],
      aliasExtra: {},

      addTransaction: (tx) => {
        const id = `t-${Date.now().toString(36)}`;
        set((s) => ({ transactions: [{ ...tx, id }, ...s.transactions] }));
        syncMutation('addTransaction', {
          ledgerId: tx.ledgerId ?? 'personal',
          accountId: tx.account,
          amount: tx.amount,
          merchant: tx.merchant,
          categoryId: tx.category,
          date: tx.date,
          time: tx.time,
          note: tx.note,
          status: tx.pending ? 'pending' : 'confirmed',
        });
        return id;
      },

      updateTransaction: (id, patch) => {
        set((s) => ({
          transactions: s.transactions.map((t) => (t.id === id ? { ...t, ...patch } : t)),
        }));
        syncMutation('updateTransaction', { id, patch });
      },

      deleteTransaction: (id) => {
        set((s) => ({ transactions: s.transactions.filter((t) => t.id !== id) }));
        syncMutation('deleteTransaction', { id });
      },

      confirmPending: (id) => {
        set((s) => ({ pending: s.pending.filter((p) => p.id !== id) }));
        syncMutation('confirmPending', { id });
      },

      cancelPending: (id) => {
        set((s) => ({ pending: s.pending.filter((p) => p.id !== id) }));
        syncMutation('cancelPending', { id });
      },

      confirmAllPending: () => {
        set({ pending: [] });
        syncMutation('confirmAllPending');
      },

      setBudget: (categoryId, amount) => {
        set((s) => ({ budgetOverrides: { ...s.budgetOverrides, [categoryId]: amount } }));
        syncMutation('setBudget', { categoryId, amount });
      },

      setAccountDetails: (accountId, patch) => {
        set((s) => ({
          accountOverrides: {
            ...s.accountOverrides,
            [accountId]: { ...s.accountOverrides[accountId], ...patch },
          },
        }));
        syncMutation('setAccountDetails', { accountId, patch });
      },

      updateRecurringSplit: (templateId, index, pct) => {
        set((s) => ({
          recurring: s.recurring.map((t) =>
            t.id === templateId && t.splits
              ? { ...t, splits: t.splits.map((sp, i) => (i === index ? { ...sp, pct } : sp)) }
              : t,
          ),
        }));
        syncMutation('updateRecurringSplit', { templateId, index, pct });
      },

      verifyCounterparty: (id) => {
        set((s) => ({ verifiedExtra: s.verifiedExtra.includes(id) ? s.verifiedExtra : [...s.verifiedExtra, id] }));
        syncMutation('verifyCounterparty', { id });
      },

      addAlias: (id, alias) => {
        set((s) => ({
          aliasExtra: { ...s.aliasExtra, [id]: [...(s.aliasExtra[id] ?? []), alias] },
        }));
        syncMutation('addAlias', { id, alias });
      },

      // Transfers and recurring posts are created on the server (they're
      // multi-row / relational); the server response refreshes the store.
      createTransfer: (input) => {
        syncMutation('createTransfer', { ...input });
      },

      postRecurring: (templateId) => {
        syncMutation('postRecurring', { templateId });
      },

      reset: () => {
        set({
          transactions: SEED_TX,
          pending: SEED_PENDING,
          recurring: SEED_RECURRING,
          budgetOverrides: {},
          accountOverrides: {},
          verifiedExtra: [],
          aliasExtra: {},
        });
        syncMutation('reset');
      },
  }),
);
