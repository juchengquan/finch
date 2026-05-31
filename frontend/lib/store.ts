'use client';

import { create } from 'zustand';
import transactionsData from '@/data/transactions.json';
import scheduledData from '@/data/scheduled-templates.json';
import type { AccountRow } from '@/lib/db/queries/accounts';
import type { AccountGroupRow } from '@/lib/db/queries/accountGroups';
import type { BudgetRow, BudgetType, BudgetPatch } from '@/lib/db/queries/budgets';
import type { BudgetGroupRow } from '@/lib/db/queries/budgetGroups';
import type { CategoryRow } from '@/lib/db/queries/categories';
import type { Counterparty } from '@/lib/db/queries/counterparties';
import type { ExchangeRate, Device } from '@/lib/db/queries/system';
import type { Tag } from '@/lib/db/queries/tags';

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
  /** Classification. Optional only for the pre-hydration seed; the DB always sets
   *  it. 'adjustment' = manual balance reconciliation (excluded from spend/flow). */
  kind?: 'income' | 'expense' | 'transfer' | 'adjustment';
  ledgerId?: string;
  transferGroupId?: string;
  /** The scheduled template this row was auto-generated from (if any). */
  sourceTemplateId?: string;
  tags?: string[];
  /** Ad-hoc category splits. When present, these override `category` /
   * `amount` for category aggregations (categorySpend / budgets / etc.). */
  splits?: TxSplit[];
}

export interface TxSplit {
  id: string;
  categoryId: string | null;
  amount: number;       // signed, in the tx's native currency
  amountBase: number;   // signed, in the ledger's base currency
  description: string | null;
}

export interface TxSplitInput {
  categoryId: string | null;
  amount: number;
  description?: string | null;
}

export interface TransferInput {
  fromAccountId: string;
  toAccountId: string;
  /** Sent magnitude, in the from-account's currency. */
  fromAmount: number;
  /** Optional received magnitude, in the to-account's currency. When omitted,
   *  derived from the rates table at `date`. Set this to pin both sides
   *  (e.g. matching a bank statement where the actual conversion differs
   *  from the mid-rate); the rate becomes `toAmount / fromAmount`. */
  toAmount?: number;
  date: string;
  note?: string;
}

export interface ScheduledSplit {
  account: string;
  pct: number;
  abs: number | null;
  label: string;
}

export interface ScheduledTemplate {
  id: string;
  name: string;
  type: string;
  amount: number | null;
  varies?: number;
  frequency: string;
  dayOfMonth: number;
  weekDay?: number;
  account: string;
  from?: string;
  autoPost: number;
  nextRun: string;
  lastRun: string;
  color?: string | null;
  category?: string | null;
  startDate?: string;
  endDate?: string | null;
  maxExecutions?: number | null;
  splits?: ScheduledSplit[];
}

// Editable account fields, applied as a patch against the real accounts table.
export interface AccountPatch {
  name?: string;
  type?: string;
  currency?: string;
  color?: string | null;
  groupId?: string | null;
  /** Per-account net-worth flag (0/1). Defaulted from `type` at create time. */
  includeInNetWorth?: number;
}

export interface NewAccountInput {
  name: string;
  type: string;
  currency?: string;
  groupId?: string | null;
  openingBalance?: number;
  color?: string | null;
  ledgerId?: string;
}

const SEED_TX = transactionsData as Tx[];
const SEED_SCHEDULED = scheduledData as ScheduledTemplate[];

// Input for creating a named budget from the UI (booleans here, normalised to
// the DB's 0/1 ints on the way out).
export interface NewBudgetInput {
  name: string;
  type: BudgetType;
  amount: number;
  groupId?: string | null;
  frequency?: string;
  startDate?: string;
  endDate?: string | null;
  isRecurring?: boolean;
  rollover?: boolean;
  rolloverLimit?: number | null;
  accountIds?: string[];
  categoryIds?: string[];
  tagIds?: string[];
  warningPct?: number;
  saved?: number;
  ledgerId?: string;
}

interface FinanceState {
  transactions: Tx[];
  scheduled: ScheduledTemplate[];
  // Reference / derived data projected from the server DB (read-only mirror).
  accounts: AccountRow[];
  accountGroups: AccountGroupRow[];
  budgets: BudgetRow[];
  budgetGroups: BudgetGroupRow[];
  categories: CategoryRow[];
  counterparties: Counterparty[];
  exchangeRates: ExchangeRate[];
  devices: Device[];
  tags: Tag[];
  /** Ordered section ids for the mobile bottom bar (empty = client default). */
  mobileTabIds: string[];
  /** Per-ledger display currency (ledgerId → currency). Missing = ledger's base. */
  displayCurrencyByLedger: Record<string, string>;

  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  adjustAccountBalance: (accountId: string, targetBalance: number, note?: string) => void;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  setMobileTabIds: (ids: string[]) => void;
  setDisplayCurrency: (ledgerId: string, currency: string) => void;
  createAccount: (input: NewAccountInput) => string;
  updateAccount: (id: string, patch: AccountPatch) => void;
  archiveAccount: (id: string) => void;
  createAccountGroup: (input: { name: string; ledgerId?: string }) => string;
  updateAccountGroup: (id: string, patch: { name?: string }) => void;
  deleteAccountGroup: (id: string) => void;
  createBudget: (input: NewBudgetInput) => string;
  updateBudget: (id: string, patch: BudgetPatch) => void;
  updateBudgetCycle: (
    id: string,
    patch: { frequency: string; startDate: string; amount?: number; endDate?: string | null },
  ) => void;
  clearPendingAmount: (id: string) => void;
  removeBudget: (id: string) => void;
  contributeBudget: (id: string, amount: number) => void;
  createBudgetGroup: (input: { name: string; ledgerId?: string }) => string;
  updateBudgetGroup: (id: string, patch: { name?: string }) => void;
  deleteBudgetGroup: (id: string) => void;
  updateScheduledSplit: (templateId: string, index: number, pct: number) => void;
  addScheduledSplit: (templateId: string, account: string, pct: number) => void;
  removeScheduledSplit: (templateId: string, index: number) => void;
  verifyCounterparty: (id: string) => void;
  unverifyCounterparty: (id: string) => void;
  createTransfer: (input: TransferInput) => void;
  createCategory: (input: { name: string; type?: string; icon?: string; color?: string; ledgerId?: string }) => void;
  updateCategory: (id: string, patch: { name?: string; type?: string; icon?: string | null; color?: string | null }) => void;
  deleteCategory: (id: string) => void;
  createTag: (input: { name: string; color?: string; ledgerId?: string }) => string;
  setTransactionTags: (transactionId: string, tagIds: string[]) => void;
  setTransactionSplits: (transactionId: string, splits: TxSplitInput[]) => void;
  updateTag: (id: string, patch: { name?: string; color?: string | null }) => void;
  deleteTag: (id: string) => void;
  createScheduled: (input: { name: string; type?: string; amount?: number | null; frequency?: string; dayOfMonth?: number; weekDay?: number; account?: string; from?: string; autoPost?: boolean; color?: string | null; category?: string | null; startDate?: string; endDate?: string | null; maxExecutions?: number | null; ledgerId?: string }) => string;
  updateScheduled: (id: string, patch: { name?: string; amount?: number | null; frequency?: string; dayOfMonth?: number; weekDay?: number; autoPost?: number; color?: string | null; category?: string | null; endDate?: string | null; maxExecutions?: number | null }) => void;
  deleteScheduled: (id: string) => void;
  updateTransfer: (id: string, patch: { fromAmount?: number; toAmount?: number; date?: string; note?: string | null }) => void;
  deleteTransfer: (id: string) => void;
  createCounterparty: (input: { name: string; ledgerId?: string }) => string;
  updateCounterparty: (id: string, patch: { name?: string }) => void;
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
      scheduled: SEED_SCHEDULED,
      accounts: [],
      accountGroups: [],
      budgets: [],
      budgetGroups: [],
      categories: [],
      counterparties: [],
      exchangeRates: [],
      devices: [],
      tags: [],
      mobileTabIds: [],
      displayCurrencyByLedger: {},

      setMobileTabIds: (ids) => {
        set({ mobileTabIds: ids });
        syncMutation('setMobileTabIds', { ids });
      },

      setDisplayCurrency: (ledgerId, currency) => {
        set((s) => ({ displayCurrencyByLedger: { ...s.displayCurrencyByLedger, [ledgerId]: currency } }));
        syncMutation('setDisplayCurrency', { ledgerId, currency });
      },

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

      createAccountGroup: (input) => {
        const id = `ag-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        set((s) => ({
          accountGroups: [
            ...s.accountGroups,
            { id, ledgerId, name: input.name, sortOrder: s.accountGroups.length },
          ],
        }));
        syncMutation('createAccountGroup', { id, ledgerId, name: input.name });
        return id;
      },

      updateAccountGroup: (id, patch) => {
        set((s) => ({ accountGroups: s.accountGroups.map((g) => (g.id === id ? { ...g, ...patch } : g)) }));
        syncMutation('updateAccountGroup', { id, patch });
      },

      deleteAccountGroup: (id) => {
        set((s) => ({
          accountGroups: s.accountGroups.filter((g) => g.id !== id),
          // accounts.group_id is SET NULL by the FK; mirror that optimistically.
          accounts: s.accounts.map((a) => (a.groupId === id ? { ...a, groupId: null, groupName: null } : a)),
        }));
        syncMutation('deleteAccountGroup', { id });
      },

      createBudget: (input) => {
        const id = `bgt-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        const isRecurring = input.isRecurring != null ? (input.isRecurring ? 1 : 0) : input.type === 'income' ? 0 : 1;
        const row: BudgetRow = {
          id,
          ledgerId,
          groupId: input.groupId ?? null,
          name: input.name,
          type: input.type,
          amount: input.amount,
          saved: input.saved ?? 0,
          carryForward: 0,
          frequency: input.frequency ?? 'monthly',
          startDate: input.startDate ?? new Date().toISOString().slice(0, 10),
          endDate: input.endDate ?? null,
          isRecurring,
          rollover: input.rollover ? 1 : 0,
          rolloverLimit: input.rolloverLimit ?? null,
          pendingAmount: null,
          lastRolledPeriod: null,
          accountIds: input.accountIds ?? [],
          categoryIds: input.categoryIds ?? [],
          tagIds: input.tagIds ?? [],
          warningPct: input.warningPct ?? 80,
        };
        set((s) => ({ budgets: [...s.budgets, row] }));
        syncMutation('createBudget', {
          id,
          ledgerId,
          groupId: row.groupId,
          name: row.name,
          type: row.type,
          amount: row.amount,
          saved: row.saved,
          frequency: row.frequency,
          startDate: row.startDate,
          endDate: row.endDate,
          isRecurring: row.isRecurring,
          rollover: row.rollover,
          rolloverLimit: row.rolloverLimit,
          accountIds: row.accountIds,
          categoryIds: row.categoryIds,
          tagIds: row.tagIds,
          warningPct: row.warningPct,
        });
        return id;
      },

      updateBudget: (id, patch) => {
        set((s) => ({
          budgets: s.budgets.map((b) => {
            if (b.id !== id) return b;
            // Mirror the server-side staging rule: amount-only patches on
            // recurring budgets write to pendingAmount, not amount.
            const keys = Object.keys(patch).filter(
              (k) => (patch as Record<string, unknown>)[k] !== undefined,
            );
            const amountOnly = keys.length === 1 && keys[0] === 'amount';
            if (amountOnly && b.isRecurring === 1) {
              return { ...b, pendingAmount: Number(patch.amount) };
            }
            return { ...b, ...patch };
          }),
        }));
        syncMutation('updateBudget', { id, patch });
      },

      updateBudgetCycle: (id, patch) => {
        set((s) => ({
          budgets: s.budgets.map((b) => {
            if (b.id !== id) return b;
            const nextAmount = patch.amount ?? b.amount;
            return {
              ...b,
              amount: nextAmount,
              frequency: patch.frequency,
              startDate: patch.startDate,
              endDate: patch.endDate === undefined ? b.endDate : patch.endDate,
              pendingAmount: null,
              lastRolledPeriod: null,
            };
          }),
        }));
        syncMutation('updateBudgetCycle', { id, patch });
      },

      clearPendingAmount: (id) => {
        set((s) => ({
          budgets: s.budgets.map((b) => (b.id === id ? { ...b, pendingAmount: null } : b)),
        }));
        syncMutation('clearPendingAmount', { id });
      },

      removeBudget: (id) => {
        set((s) => ({ budgets: s.budgets.filter((b) => b.id !== id) }));
        syncMutation('removeBudget', { id });
      },

      contributeBudget: (id, amount) => {
        set((s) => ({
          budgets: s.budgets.map((b) => (b.id === id ? { ...b, saved: Math.max(0, b.saved + amount) } : b)),
        }));
        syncMutation('contributeBudget', { id, amount });
      },

      createBudgetGroup: (input) => {
        const id = `bgg-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        set((s) => ({
          budgetGroups: [...s.budgetGroups, { id, ledgerId, name: input.name, sortOrder: s.budgetGroups.length }],
        }));
        syncMutation('createBudgetGroup', { id, ledgerId, name: input.name });
        return id;
      },

      updateBudgetGroup: (id, patch) => {
        set((s) => ({ budgetGroups: s.budgetGroups.map((g) => (g.id === id ? { ...g, ...patch } : g)) }));
        syncMutation('updateBudgetGroup', { id, patch });
      },

      deleteBudgetGroup: (id) => {
        set((s) => ({
          budgetGroups: s.budgetGroups.filter((g) => g.id !== id),
          // budgets.group_id is SET NULL by the FK; mirror that optimistically.
          budgets: s.budgets.map((b) => (b.groupId === id ? { ...b, groupId: null } : b)),
        }));
        syncMutation('deleteBudgetGroup', { id });
      },

      updateScheduledSplit: (templateId, index, pct) => {
        set((s) => ({
          scheduled: s.scheduled.map((t) =>
            t.id === templateId && t.splits
              ? { ...t, splits: t.splits.map((sp, i) => (i === index ? { ...sp, pct } : sp)) }
              : t,
          ),
        }));
        syncMutation('updateScheduledSplit', { templateId, index, pct });
      },

      addScheduledSplit: (templateId, account, pct) => {
        set((s) => ({
          scheduled: s.scheduled.map((t) =>
            t.id === templateId ? { ...t, splits: [...(t.splits ?? []), { account, pct, abs: null, label: '' }] } : t,
          ),
        }));
        syncMutation('addScheduledSplit', { templateId, account, pct });
      },

      removeScheduledSplit: (templateId, index) => {
        set((s) => ({
          scheduled: s.scheduled.map((t) =>
            t.id === templateId && t.splits ? { ...t, splits: t.splits.filter((_, i) => i !== index) } : t,
          ),
        }));
        syncMutation('removeScheduledSplit', { templateId, index });
      },

      verifyCounterparty: (id) => {
        set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, verified: true } : c)) }));
        syncMutation('verifyCounterparty', { id });
      },

      unverifyCounterparty: (id) => {
        set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, verified: false } : c)) }));
        syncMutation('unverifyCounterparty', { id });
      },

      // Transfers are created on the server (multi-row / relational); the server
      // response refreshes the store. (Scheduled "post" is called directly from
      // the scheduled page so it can surface account-match errors.)
      createTransfer: (input) => {
        syncMutation('createTransfer', { ...input });
      },

      createCategory: (input) => {
        const ledgerId = input.ledgerId ?? 'personal';
        const id = `cat-${Date.now().toString(36)}`;
        const type = input.type ?? 'expense';
        const icon = input.icon ?? null;
        const color = input.color ?? null;
        set((s) => ({ categories: [...s.categories, { id, ledgerId, name: input.name, type, icon, color }] }));
        syncMutation('createCategory', { ledgerId, name: input.name, type, icon, color });
      },

      updateCategory: (id, patch) => {
        set((s) => ({ categories: s.categories.map((c) => (c.id === id ? { ...c, ...patch } : c)) }));
        syncMutation('updateCategory', { id, patch });
      },

      deleteCategory: (id) => {
        set((s) => ({ categories: s.categories.filter((c) => c.id !== id) }));
        syncMutation('deleteCategory', { id });
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

      setTransactionSplits: (transactionId, splits) => {
        set((s) => ({
          transactions: s.transactions.map((t) => {
            if (t.id !== transactionId) return t;
            if (!splits.length) {
              const { splits: _drop, ...rest } = t;
              void _drop;
              return rest;
            }
            const ratio = t.amount !== 0 && t.nativeAmount != null && t.nativeAmount !== 0
              ? t.amount / t.nativeAmount
              : 1;
            const optimistic: TxSplit[] = splits.map((sp, i) => ({
              id: `${transactionId}-s-${i}`,
              categoryId: sp.categoryId,
              amount: sp.amount,
              amountBase: Math.round(sp.amount * ratio * 100) / 100,
              description: sp.description ?? null,
            }));
            return { ...t, splits: optimistic };
          }),
        }));
        syncMutation('setTransactionSplits', {
          id: transactionId,
          splits: splits.map((s) => ({
            categoryId: s.categoryId,
            amount: s.amount,
            description: s.description ?? null,
          })),
        });
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

      createScheduled: (input) => {
        const id = `sch-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        const type = input.type ?? 'expense';
        const frequency = input.frequency ?? 'monthly';
        const dayOfMonth = input.dayOfMonth ?? 1;
        const weekDay = input.weekDay;
        const autoPost = input.autoPost ? 1 : 0;
        const amount = input.amount ?? null;
        const color = input.color ?? null;
        const account = input.account ?? '';
        const category = input.category ?? null;
        const startDate = input.startDate ?? '';
        const endDate = input.endDate ?? null;
        const maxExecutions = input.maxExecutions ?? null;
        set((s) => ({
          scheduled: [
            ...s.scheduled,
            { id, name: input.name, type, amount, frequency, dayOfMonth, weekDay, account, from: input.from, autoPost, nextRun: '', lastRun: '', color, category, startDate, endDate, maxExecutions },
          ],
        }));
        syncMutation('createScheduled', { id, ledgerId, name: input.name, type, amount, frequency, dayOfMonth, weekDay: weekDay ?? null, account, from: input.from ?? null, autoPost: !!input.autoPost, color, category, startDate, endDate, maxExecutions });
        return id;
      },

      updateScheduled: (id, patch) => {
        set((s) => ({ scheduled: s.scheduled.map((t) => (t.id === id ? { ...t, ...patch } : t)) }));
        syncMutation('updateScheduled', { id, patch });
      },

      deleteScheduled: (id) => {
        set((s) => ({ scheduled: s.scheduled.filter((t) => t.id !== id) }));
        syncMutation('deleteScheduled', { id });
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

      createCounterparty: (input) => {
        const id = `cp-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        set((s) => ({ counterparties: [...s.counterparties, { id, ledgerId, name: input.name, verified: false }] }));
        syncMutation('createCounterparty', { id, ledgerId, name: input.name });
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
          scheduled: SEED_SCHEDULED,
        });
        syncMutation('reset');
      },
  }),
);
