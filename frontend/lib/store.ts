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
  /** Manual balance reconciliation (excluded from category spend / cash flow). */
  isAdjustment?: boolean;
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
  // Reference / derived data projected from the server DB (read-only mirror).
  accounts: AccountRow[];
  budgetByCategory: Record<string, number>;
  categories: CategoryRow[];
  counterparties: Counterparty[];
  exchangeRates: ExchangeRate[];
  devices: Device[];
  goals: Goal[];
  tags: Tag[];
  subscriptions: Subscription[];
  scheduledItems: ScheduledItem[];

  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  adjustAccountBalance: (accountId: string, targetBalance: number, note?: string) => void;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  setBudget: (categoryId: string, amount: number) => void;
  deleteBudget: (categoryId: string) => void;
  createAccount: (input: NewAccountInput) => string;
  updateAccount: (id: string, patch: AccountPatch) => void;
  archiveAccount: (id: string) => void;
  updateRecurringSplit: (templateId: string, index: number, pct: number) => void;
  addRecurringSplit: (templateId: string, account: string, pct: number) => void;
  removeRecurringSplit: (templateId: string, index: number) => void;
  verifyCounterparty: (id: string) => void;
  unverifyCounterparty: (id: string) => void;
  addAlias: (id: string, alias: string) => void;
  removeAlias: (id: string, alias: string) => void;
  createTransfer: (input: TransferInput) => void;
  createCategory: (input: { name: string; type?: string; icon?: string; hue?: number; ledgerId?: string }) => void;
  renameCategory: (id: string, name: string) => void;
  updateCategory: (id: string, patch: { name?: string; type?: string; icon?: string | null; hue?: number | null }) => void;
  deleteCategory: (id: string) => void;
  createGoal: (input: { name: string; target: number; eta?: string; hue?: number; ledgerId?: string }) => void;
  contributeGoal: (id: string, amount: number) => void;
  updateGoal: (id: string, patch: { name?: string; target?: number; eta?: string | null }) => void;
  deleteGoal: (id: string) => void;
  createTag: (input: { name: string; color?: string; ledgerId?: string }) => string;
  setTransactionTags: (transactionId: string, tagIds: string[]) => void;
  updateTag: (id: string, patch: { name?: string; color?: string | null }) => void;
  deleteTag: (id: string) => void;
  createSubscription: (input: { name: string; amount: number; cadence?: string; next?: string; hue?: number; ledgerId?: string }) => void;
  updateSubscription: (id: string, patch: { name?: string; amount?: number; cadence?: string; next?: string | null }) => void;
  deleteSubscription: (id: string) => void;
  createRecurring: (input: { name: string; type?: string; amount?: number | null; frequency?: string; dayOfMonth?: number; account: string; from?: string; autoPost?: boolean; ledgerId?: string }) => string;
  updateRecurring: (id: string, patch: { name?: string; amount?: number | null; frequency?: string; dayOfMonth?: number; autoPost?: number }) => void;
  deleteRecurring: (id: string) => void;
  updateTransfer: (id: string, patch: { amount?: number; date?: string; note?: string | null }) => void;
  deleteTransfer: (id: string) => void;
  createScheduledItem: (input: { label: string; amount: number; day: number; month: string; type?: string; color?: string; ledgerId?: string }) => void;
  updateScheduledItem: (id: string, patch: { day?: number; month?: string; label?: string; amount?: number; type?: string; color?: string | null }) => void;
  deleteScheduledItem: (id: string) => void;
  createCounterparty: (input: { name: string; category?: string | null; ledgerId?: string }) => string;
  updateCounterparty: (id: string, patch: { name?: string; category?: string | null }) => void;
  deleteCounterparty: (id: string) => void;
  setExchangeRate: (input: { date: string; currency: string; rate: number; source?: string | null }) => void;
  deleteExchangeRate: (date: string, currency: string) => void;
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
      accounts: [],
      budgetByCategory: {},
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

      adjustAccountBalance: (accountId, targetBalance, note) => {
        // The server rewrites/inserts the delta + recomputes; adopt the re-projection.
        syncMutation('adjustAccountBalance', { accountId, targetBalance, note });
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
        set((s) => ({ budgetByCategory: { ...s.budgetByCategory, [categoryId]: amount } }));
        syncMutation('setBudget', { categoryId, amount });
      },

      deleteBudget: (categoryId) => {
        set((s) => {
          const next = { ...s.budgetByCategory };
          delete next[categoryId];
          return { budgetByCategory: next };
        });
        syncMutation('deleteBudget', { categoryId });
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

      addRecurringSplit: (templateId, account, pct) => {
        set((s) => ({
          recurring: s.recurring.map((t) =>
            t.id === templateId ? { ...t, splits: [...(t.splits ?? []), { account, pct, abs: null, label: '' }] } : t,
          ),
        }));
        syncMutation('addRecurringSplit', { templateId, account, pct });
      },

      removeRecurringSplit: (templateId, index) => {
        set((s) => ({
          recurring: s.recurring.map((t) =>
            t.id === templateId && t.splits ? { ...t, splits: t.splits.filter((_, i) => i !== index) } : t,
          ),
        }));
        syncMutation('removeRecurringSplit', { templateId, index });
      },

      verifyCounterparty: (id) => {
        set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, verified: true } : c)) }));
        syncMutation('verifyCounterparty', { id });
      },

      unverifyCounterparty: (id) => {
        set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, verified: false } : c)) }));
        syncMutation('unverifyCounterparty', { id });
      },

      addAlias: (id, alias) => {
        set((s) => ({
          counterparties: s.counterparties.map((c) =>
            c.id === id && !c.aliases.includes(alias) ? { ...c, aliases: [...c.aliases, alias] } : c,
          ),
        }));
        syncMutation('addAlias', { id, alias });
      },

      removeAlias: (id, alias) => {
        set((s) => ({
          counterparties: s.counterparties.map((c) =>
            c.id === id ? { ...c, aliases: c.aliases.filter((a) => a !== alias) } : c,
          ),
        }));
        syncMutation('removeAlias', { id, alias });
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
        const hue = input.hue ?? null;
        set((s) => ({ categories: [...s.categories, { id, ledgerId, name: input.name, parentName: null, type, icon, hue }] }));
        syncMutation('createCategory', { ledgerId, name: input.name, type, icon, hue });
      },

      renameCategory: (id, name) => {
        set((s) => ({ categories: s.categories.map((c) => (c.id === id ? { ...c, name } : c)) }));
        syncMutation('renameCategory', { id, name });
      },

      updateCategory: (id, patch) => {
        set((s) => ({ categories: s.categories.map((c) => (c.id === id ? { ...c, ...patch } : c)) }));
        syncMutation('updateCategory', { id, patch });
      },

      deleteCategory: (id) => {
        set((s) => ({ categories: s.categories.filter((c) => c.id !== id) }));
        syncMutation('deleteCategory', { id });
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

      updateGoal: (id, patch) => {
        set((s) => ({ goals: s.goals.map((g) => (g.id === id ? { ...g, ...patch } : g)) }));
        syncMutation('updateGoal', { id, patch });
      },

      deleteGoal: (id) => {
        set((s) => ({ goals: s.goals.filter((g) => g.id !== id) }));
        syncMutation('deleteGoal', { id });
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

      updateTag: (id, patch) => {
        set((s) => ({ tags: s.tags.map((t) => (t.id === id ? { ...t, ...patch } : t)) }));
        syncMutation('updateTag', { id, patch });
      },

      deleteTag: (id) => {
        set((s) => ({
          tags: s.tags.filter((t) => t.id !== id),
          transactions: s.transactions.map((t) => (t.tags ? { ...t, tags: t.tags.filter((x) => x !== id) } : t)),
        }));
        syncMutation('deleteTag', { id });
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

      updateSubscription: (id, patch) => {
        set((s) => ({ subscriptions: s.subscriptions.map((x) => (x.id === id ? { ...x, ...patch } : x)) }));
        syncMutation('updateSubscription', { id, patch });
      },

      deleteSubscription: (id) => {
        set((s) => ({ subscriptions: s.subscriptions.filter((x) => x.id !== id) }));
        syncMutation('deleteSubscription', { id });
      },

      createRecurring: (input) => {
        const id = `rt-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        const type = input.type ?? 'expense';
        const frequency = input.frequency ?? 'monthly';
        const dayOfMonth = input.dayOfMonth ?? 1;
        const autoPost = input.autoPost ? 1 : 0;
        const amount = input.amount ?? null;
        set((s) => ({
          recurring: [
            ...s.recurring,
            { id, name: input.name, type, amount, frequency, dayOfMonth, account: input.account, from: input.from, autoPost, nextRun: '', lastRun: '' },
          ],
        }));
        syncMutation('createRecurring', { id, ledgerId, name: input.name, type, amount, frequency, dayOfMonth, account: input.account, from: input.from ?? null, autoPost: !!input.autoPost });
        return id;
      },

      updateRecurring: (id, patch) => {
        set((s) => ({ recurring: s.recurring.map((t) => (t.id === id ? { ...t, ...patch } : t)) }));
        syncMutation('updateRecurring', { id, patch });
      },

      deleteRecurring: (id) => {
        set((s) => ({ recurring: s.recurring.filter((t) => t.id !== id) }));
        syncMutation('deleteRecurring', { id });
      },

      updateTransfer: (id, patch) => {
        // Both legs are rewritten + balances recomputed server-side; adopt the
        // server's re-projection rather than re-deriving the legs client-side.
        syncMutation('updateTransfer', { id, patch });
      },

      deleteTransfer: (id) => {
        // A transfer is two transactions sharing a group id; drop both optimistically.
        set((s) => ({ transactions: s.transactions.filter((t) => t.transferGroupId !== id) }));
        syncMutation('deleteTransfer', { id });
      },

      createScheduledItem: (input) => {
        const id = `sch-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        const type = input.type ?? 'bill';
        const color = input.color ?? null;
        set((s) => ({ scheduledItems: [...s.scheduledItems, { id, ledgerId, day: input.day, month: input.month, label: input.label, amount: input.amount, type, color }] }));
        syncMutation('createScheduledItem', { id, ledgerId, day: input.day, month: input.month, label: input.label, amount: input.amount, type, color });
      },

      updateScheduledItem: (id, patch) => {
        set((s) => ({ scheduledItems: s.scheduledItems.map((x) => (x.id === id ? { ...x, ...patch } : x)) }));
        syncMutation('updateScheduledItem', { id, patch });
      },

      deleteScheduledItem: (id) => {
        set((s) => ({ scheduledItems: s.scheduledItems.filter((x) => x.id !== id) }));
        syncMutation('deleteScheduledItem', { id });
      },

      createCounterparty: (input) => {
        const id = `cp-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        const category = input.category ?? null;
        set((s) => ({ counterparties: [...s.counterparties, { id, ledgerId, name: input.name, aliases: [], category, verified: false }] }));
        syncMutation('createCounterparty', { id, ledgerId, name: input.name, category });
        return id;
      },

      updateCounterparty: (id, patch) => {
        set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, ...patch } : c)) }));
        syncMutation('updateCounterparty', { id, patch });
      },

      deleteCounterparty: (id) => {
        set((s) => ({ counterparties: s.counterparties.filter((c) => c.id !== id) }));
        syncMutation('deleteCounterparty', { id });
      },

      setExchangeRate: (input) => {
        const currency = input.currency.trim().toUpperCase();
        const source = input.source ?? null;
        set((s) => {
          const rest = s.exchangeRates.filter((r) => !(r.date === input.date && r.currency === currency));
          return { exchangeRates: [...rest, { date: input.date, currency, rate: input.rate, source }] };
        });
        syncMutation('setExchangeRate', { date: input.date, currency, rate: input.rate, source });
      },

      deleteExchangeRate: (date, currency) => {
        const upper = currency.toUpperCase();
        set((s) => ({ exchangeRates: s.exchangeRates.filter((r) => !(r.date === date && r.currency === upper)) }));
        syncMutation('deleteExchangeRate', { date, currency: upper });
      },

      reset: () => {
        set({
          transactions: SEED_TX,
          recurring: SEED_RECURRING,
        });
        syncMutation('reset');
      },
  }),
);
