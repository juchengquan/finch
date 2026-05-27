'use client';

import { create } from 'zustand';
import transactionsData from '@/data/transactions.json';
import recurringData from '@/data/recurring-templates.json';
import type { AccountRow } from '@/lib/db/queries/accounts';
import type { CategoryRow } from '@/lib/db/queries/categories';
import type { Counterparty } from '@/lib/db/queries/counterparties';
import type { ExchangeRate, Device } from '@/lib/db/queries/system';
import type { Goal } from '@/lib/db/queries/goals';
import type { Tag } from '@/lib/db/queries/tags';
import type { Subscription, ScheduledItem } from '@/lib/db/queries/planning';

export interface Tx {
  id: string;
  merchant: string;
  category: string | null;
  amount: number;
  /** Currency the expense was entered in. Omitted/equal to the ledger base for same-currency entries. */
  currency?: string;
  /** Signed amount in `currency`; `amount` is always the ledger-base figure that drives balances. */
  nativeAmount?: number;
  account: string;
  date: string;
  time?: string;
  note?: string;
  pending?: boolean;
  recurring?: boolean;
  kind?: string;
  ledgerId?: string;
  transferGroupId?: string;
  tags?: string[];
}

export interface TransferInput {
  fromAccountId: string;
  toAccountId: string;
  amount: number;
  date: string;
  note?: string;
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

// Editable account fields, applied as a patch against the real accounts table.
export interface AccountPatch {
  name?: string;
  type?: string;
  last4?: string | null;
  institution?: string | null;
  routing?: string | null;
  color?: string | null;
  groupId?: string | null;
}

export interface NewAccountInput {
  name: string;
  type: string;
  currency?: string;
  groupId?: string | null;
  openingBalance?: number;
  color?: string | null;
  last4?: string | null;
  ledgerId?: string;
}

const SEED_TX = transactionsData as Tx[];
const SEED_RECURRING = recurringData as RecurringTemplate[];

interface FinanceState {
  transactions: Tx[];
  recurring: RecurringTemplate[];
  // Editable overrides on otherwise-static mock data, persisted.
  budgetOverrides: Record<string, number>;
  verifiedExtra: string[];
  aliasExtra: Record<string, string[]>;
  // Reference / derived data projected from the server DB (read-only mirror).
  accounts: AccountRow[];
  categories: CategoryRow[];
  counterparties: Counterparty[];
  exchangeRates: ExchangeRate[];
  devices: Device[];
  goals: Goal[];
  tags: Tag[];
  subscriptions: Subscription[];
  scheduledItems: ScheduledItem[];

  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  setBudget: (categoryId: string, amount: number) => void;
  createAccount: (input: NewAccountInput) => string;
  updateAccount: (id: string, patch: AccountPatch) => void;
  archiveAccount: (id: string) => void;
  updateRecurringSplit: (templateId: string, index: number, pct: number) => void;
  verifyCounterparty: (id: string) => void;
  addAlias: (id: string, alias: string) => void;
  createTransfer: (input: TransferInput) => void;
  createCategory: (input: { name: string; type?: string; icon?: string; ledgerId?: string }) => void;
  renameCategory: (id: string, name: string) => void;
  createGoal: (input: { name: string; target: number; eta?: string; hue?: number; ledgerId?: string }) => void;
  contributeGoal: (id: string, amount: number) => void;
  createTag: (input: { name: string; color?: string; ledgerId?: string }) => string;
  setTransactionTags: (transactionId: string, tagIds: string[]) => void;
  createSubscription: (input: { name: string; amount: number; cadence?: string; next?: string; hue?: number; ledgerId?: string }) => void;
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
      recurring: SEED_RECURRING,
      budgetOverrides: {},
      verifiedExtra: [],
      aliasExtra: {},
      accounts: [],
      categories: [],
      counterparties: [],
      exchangeRates: [],
      devices: [],
      goals: [],
      tags: [],
      subscriptions: [],
      scheduledItems: [],

      addTransaction: (tx) => {
        const id = `t-${Date.now().toString(36)}`;
        set((s) => ({ transactions: [{ ...tx, id }, ...s.transactions] }));
        syncMutation('addTransaction', {
          ledgerId: tx.ledgerId ?? 'personal',
          accountId: tx.account,
          // `amount` is native (what the user entered); `amountBase` drives balances.
          amount: tx.nativeAmount ?? tx.amount,
          amountBase: tx.amount,
          currency: tx.currency,
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

      // Pending items are transactions with status='pending'. Confirming flips the
      // status (flowing into reports/balances); cancelling voids the transaction.
      confirmPending: (id) => {
        set((s) => ({ transactions: s.transactions.map((t) => (t.id === id ? { ...t, pending: false } : t)) }));
        syncMutation('confirmTransaction', { id });
      },

      cancelPending: (id) => {
        set((s) => ({ transactions: s.transactions.filter((t) => t.id !== id) }));
        syncMutation('deleteTransaction', { id });
      },

      confirmAllPending: () => {
        set((s) => ({ transactions: s.transactions.map((t) => (t.pending ? { ...t, pending: false } : t)) }));
        syncMutation('confirmAllPending');
      },

      setBudget: (categoryId, amount) => {
        set((s) => ({ budgetOverrides: { ...s.budgetOverrides, [categoryId]: amount } }));
        syncMutation('setBudget', { categoryId, amount });
      },

      createAccount: (input) => {
        const id = `acct-${Date.now().toString(36)}`;
        syncMutation('createAccount', {
          id,
          ledgerId: input.ledgerId ?? 'personal',
          name: input.name,
          type: input.type,
          currency: input.currency ?? 'SGD',
          groupId: input.groupId ?? null,
          openingBalance: input.openingBalance ?? 0,
          color: input.color ?? null,
          last4: input.last4 ?? null,
        });
        return id;
      },

      updateAccount: (id, patch) => {
        // Optimistically patch the projected row; syncMutation re-projects from the DB.
        set((s) => ({ accounts: s.accounts.map((a) => (a.id === id ? { ...a, ...patch } : a)) }));
        syncMutation('updateAccount', { id, patch });
      },

      archiveAccount: (id) => {
        set((s) => ({ accounts: s.accounts.filter((a) => a.id !== id) }));
        syncMutation('archiveAccount', { id });
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

      // Transfers are created on the server (multi-row / relational); the server
      // response refreshes the store. (Recurring "post" is called directly from
      // the recurring page so it can surface account-match errors.)
      createTransfer: (input) => {
        syncMutation('createTransfer', { ...input });
      },

      createCategory: (input) => {
        const ledgerId = input.ledgerId ?? 'personal';
        const id = `cat-${Date.now().toString(36)}`;
        const type = input.type ?? 'expense';
        const icon = input.icon ?? null;
        set((s) => ({ categories: [...s.categories, { id, ledgerId, name: input.name, parentName: null, type, icon }] }));
        syncMutation('createCategory', { ledgerId, name: input.name, type, icon });
      },

      renameCategory: (id, name) => {
        set((s) => ({ categories: s.categories.map((c) => (c.id === id ? { ...c, name } : c)) }));
        syncMutation('renameCategory', { id, name });
      },

      createGoal: (input) => {
        const ledgerId = input.ledgerId ?? 'personal';
        const id = `goal-${Date.now().toString(36)}`;
        const hue = input.hue ?? 200;
        set((s) => ({
          goals: [...s.goals, { id, ledgerId, name: input.name, target: input.target, saved: 0, eta: input.eta ?? null, hue }],
        }));
        syncMutation('createGoal', { ledgerId, name: input.name, target: input.target, eta: input.eta ?? null, hue });
      },

      contributeGoal: (id, amount) => {
        set((s) => ({ goals: s.goals.map((g) => (g.id === id ? { ...g, saved: g.saved + amount } : g)) }));
        syncMutation('contributeGoal', { id, amount });
      },

      createTag: (input) => {
        const ledgerId = input.ledgerId ?? 'personal';
        const id = `tag-${Date.now().toString(36)}`;
        const color = input.color ?? null;
        set((s) => ({ tags: [...s.tags, { id, ledgerId, name: input.name, color }] }));
        syncMutation('createTag', { id, ledgerId, name: input.name, color });
        return id;
      },

      setTransactionTags: (transactionId, tagIds) => {
        set((s) => ({
          transactions: s.transactions.map((t) => (t.id === transactionId ? { ...t, tags: tagIds } : t)),
        }));
        syncMutation('setTransactionTags', { id: transactionId, tagIds });
      },

      createSubscription: (input) => {
        const ledgerId = input.ledgerId ?? 'personal';
        const id = `sub-${Date.now().toString(36)}`;
        const cadence = input.cadence ?? 'monthly';
        const hue = input.hue ?? 200;
        set((s) => ({
          subscriptions: [...s.subscriptions, { id, ledgerId, name: input.name, amount: input.amount, cadence, next: input.next ?? null, hue }],
        }));
        syncMutation('createSubscription', { ledgerId, name: input.name, amount: input.amount, cadence, next: input.next ?? null, hue });
      },

      reset: () => {
        set({
          transactions: SEED_TX,
          recurring: SEED_RECURRING,
          budgetOverrides: {},
          verifiedExtra: [],
          aliasExtra: {},
        });
        syncMutation('reset');
      },
  }),
);
