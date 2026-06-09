'use client';

import { create } from 'zustand';
import transactionsData from '@/data/transactions.json';
import scheduledData from '@/data/scheduled-templates.json';
import type { AccountRow } from '@/lib/db/domain/accounts/types';
import type { AccountGroupRow } from '@/lib/db/domain/accountGroups/types';
import type { BudgetRow, BudgetType, BudgetPatch } from '@/lib/db/domain/budgets/types';
import type { BudgetGroupRow } from '@/lib/db/domain/budgetGroups/types';
import type { CategoryRow } from '@/lib/db/domain/categories/types';
import type { Counterparty } from '@/lib/db/domain/counterparties/types';
import type { LedgerRow } from '@/lib/db/domain/ledgers/types';
import type { ExchangeRate } from '@/lib/db/domain/_app/system.types';
import type { Tag } from '@/lib/db/domain/tags/types';
import type { Holding } from '@/lib/db/domain/holdings/types';
import type { Attachment } from '@/lib/db/domain/attachments/types';
import type { Rule } from '@/lib/rules/types';

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
  kind?: 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund';
  ledgerId?: string;
  transferGroupId?: string;
  /** The scheduled template this row was auto-generated from (if any). */
  sourceTemplateId?: string;
  /** For `kind='refund'` rows: the original expense this refund offsets. */
  refundedTransactionId?: string;
  /** Set when the description matches a row in `counterparties`. Resolved
   *  server-side at insert/update; `projectState` then overrides `merchant`
   *  with the canonical catalog name so renames follow history. */
  counterpartyId?: string;
  tags?: string[];
  /** Ad-hoc category splits. When present, these override `category` /
   * `amount` for category aggregations (categorySpend / budgets / etc.). */
  splits?: TxSplit[];
  /** Reconcile-to-statement clearing flag (RECONCILE_PLAN §2.1). Timestamp set
   *  when the user ticks this row off against a real statement; absent =
   *  uncleared. Independent of `pending` — a confirmed row can still be
   *  uncleared (logged but not yet seen on a statement). */
  clearedAt?: string | null;
  /** Rules-engine provenance (RULES_ENGINE_PLAN §2.2). Ids of the rules that
   *  touched this row. Drives the "why is this Groceries?" detail view and the
   *  engine's loop guard (rows it generated are skipped). */
  appliedRuleIds?: string[];
  /** Review triage flag (INSPIRATION_IDEAS §5.1). Timestamp when the user
   *  marked the row reviewed; absent/null = needs review. */
  reviewedAt?: string | null;
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
  /** Time-of-day "HH:MM" stamped on both legs, mirroring a normal entry. When
   *  omitted the legs carry a null time (e.g. scheduled posts). */
  time?: string;
  note?: string;
}

export interface ScheduledSplit {
  /** FK to the destination account. `account` is its display name, derived. */
  accountId: string;
  account: string;
  pct: number;
  abs: number | null;
  label: string;
}

export interface ScheduledTemplate {
  id: string;
  name: string;
  /** Description stamped onto posted transactions; falls back to `name`. */
  description?: string | null;
  type: string;
  amount: number | null;
  varies?: number;
  frequency: string;
  dayOfMonth: number;
  weekDay?: number;
  /** FK to the primary account (the destination for a transfer). `account` is
   *  its display name, derived by joining accounts at read time. */
  accountId: string;
  account: string;
  /** Source account for a transfer (FK); `from` is its display name. */
  fromAccountId?: string;
  from?: string;
  autoPost: number;
  nextRun: string;
  lastRun: string;
  color?: string | null;
  category?: string | null;
  startDate?: string;
  endDate?: string | null;
  maxExecutions?: number | null;
  /** Total payments in a finite installment plan (e.g. 24 for a 24-month
   *  phone contract). Null = ordinary recurring expense, no end in sight. */
  installmentTotal?: number | null;
  /** Payments posted so far. Auto-incremented when the template posts; when
   *  it reaches installmentTotal the template flips to inactive. */
  installmentPaid?: number;
  splits?: ScheduledSplit[];
}

// Editable account fields, applied as a patch against the real accounts table.
// Note: `currency` is intentionally absent — an account's currency is fixed at
// creation. Changing it would re-interpret every stored native `amount` and
// invalidate the locked amount_base / cached balance. To switch currency, make
// a new account.
export interface AccountPatch {
  name?: string;
  type?: string;
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
  ledgers: LedgerRow[];
  accounts: AccountRow[];
  accountGroups: AccountGroupRow[];
  budgets: BudgetRow[];
  budgetGroups: BudgetGroupRow[];
  categories: CategoryRow[];
  counterparties: Counterparty[];
  exchangeRates: ExchangeRate[];
  tags: Tag[];
  /** Per-position investment holdings inside investment-type accounts. */
  holdings: Holding[];
  /** Conditional rules engine — per-ledger if-then rules consumed by
   *  applyRules() on insert. See RULES_ENGINE_PLAN §2. */
  rules: Rule[];
  /** Receipt attachments — pointer rows. The actual photos/PDFs live on
   *  the server filesystem and are reached via GET /api/attachments/:id.
   *  RECEIPT_PHOTOS_PLAN §2.1. */
  attachments: Attachment[];
  /** Ordered section ids for the mobile bottom bar (empty = client default). */
  mobileTabIds: string[];
  /** Per-ledger display currency (ledgerId → currency). Missing = ledger's base. */
  displayCurrencyByLedger: Record<string, string>;
  /** Auto-backup frequency + retention. Persisted in app_state, mirrored here.
   *  frequencyMs: -1 = off, 0 = every change, >0 = minimum interval (ms).
   *  retention: number of `.finch.bak` files to keep on disk. */
  backupConfig: { frequencyMs: number; retention: number };

  addTransaction: (tx: Omit<Tx, 'id'> & { counterpartyId?: string | null }) => string;
  adjustAccountBalance: (accountId: string, targetBalance: number, note?: string) => void;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  /** Reconcile-to-statement: toggle a single row's cleared-against-statement
   *  flag. Optimistic update + one-column server UPDATE. */
  setCleared: (transactionId: string, cleared: boolean) => void;
  /** Review triage: toggle a single row's reviewed flag. Optimistic +
   *  one-column server UPDATE. */
  setReviewed: (transactionId: string, reviewed: boolean) => void;
  /** Mark every unreviewed confirmed row in the ledger (optionally one
   *  account) reviewed in a single server round-trip. */
  markAllReviewed: (ledgerId: string, opts?: { accountId?: string }) => void;
  /** Upload a receipt attachment for a transaction. Returns the new
   *  attachment id (and throws on failure so the UI can toast). The full
   *  ProjectedState is adopted on success. RECEIPT_PHOTOS_PLAN §5.1. */
  uploadAttachment: (transactionId: string, file: File) => Promise<string>;
  /** Delete a receipt attachment — DB row + file. Optimistic: the row
   *  drops from the projection on the round-trip. */
  removeAttachment: (id: string) => void;
  /** Finalise a reconciliation: stamps the account checkpoint and, when
   *  `postAdjustment` is true and a non-zero gap remains, posts an Adjustment
   *  transaction equal to the remainder so the cleared balance lands exactly
   *  on the statement target. */
  reconcileAccount: (args: {
    accountId: string;
    statementBalance: number;
    statementDate: string;
    postAdjustment: boolean;
  }) => void;
  /** Apply the same category to a batch of confirmed transactions in one
   *  server round-trip. `categoryId` of `null` clears the category. */
  bulkRecategorize: (ids: string[], categoryId: string | null) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  /**
   * Confirm a pending transaction with an explicit counterparty resolution
   * (chosen by the matcher / picker). `resolution` is one of:
   *   - `{ kind: 'existing', id }` — link to an existing counterparty
   *   - `{ kind: 'new', name }` — create a new unverified counterparty
   *   - `{ kind: 'skip' }` — confirm without linking (rare; the matcher
   *     offered a "skip and use raw" escape hatch in earlier design but
   *     we've decided against it; kept for forward-compatibility).
   */
  confirmPendingWithMatch: (
    id: string,
    resolution: { kind: 'existing'; id: string } | { kind: 'new'; name: string } | { kind: 'skip' },
  ) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  setMobileTabIds: (ids: string[]) => void;
  setDisplayCurrency: (ledgerId: string, currency: string) => void;
  /** Set the auto-backup frequency. `frequencyMs`: -1 = off, 0 = on every
   *  change, >0 = minimum interval (ms). Persisted in app_state. */
  setBackupFrequency: (frequencyMs: number) => void;
  /** Set the number of `.finch.bak` files kept on disk. >= 1. Persisted in
   *  app_state. */
  setBackupRetention: (retention: number) => void;
  changeLedgerBase: (ledgerId: string, newBase: string) => void;
  /** Create a ledger. Returns the new id so the caller can switch the
   *  active ledger immediately. Optimistic insert into the projected list. */
  createLedger: (input: { name: string; base: string; color?: string | null; tagline?: string | null }) => string;
  /** Update a ledger's editable cosmetic fields. Base currency lives on the
   *  dedicated `changeLedgerBase` path (it has reconversion semantics). */
  updateLedger: (id: string, patch: { name?: string; color?: string | null; tagline?: string | null }) => void;
  /** Flip `is_default` on the named ledger; clears every other ledger's flag. */
  setDefaultLedger: (id: string) => void;
  /** Delete a ledger and every child row (ordered cascade + on-disk
   *  attachment sweep). Throws on the last ledger; refuses to delete the
   *  only remaining one. */
  deleteLedger: (id: string) => void;
  createAccount: (input: NewAccountInput) => string;
  updateAccount: (id: string, patch: AccountPatch) => void;
  archiveAccount: (id: string) => void;
  unarchiveAccount: (id: string) => void;
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
  addScheduledSplit: (templateId: string, accountId: string, account: string, pct: number) => void;
  removeScheduledSplit: (templateId: string, index: number) => void;
  verifyCounterparty: (id: string) => void;
  unverifyCounterparty: (id: string) => void;
  createTransfer: (input: TransferInput) => void;
  createCategory: (input: { name: string; type?: string; icon?: string; color?: string; parentId?: string | null; ledgerId?: string }) => void;
  updateCategory: (id: string, patch: { name?: string; type?: string; icon?: string | null; color?: string | null; parentId?: string | null }) => void;
  deleteCategory: (id: string) => void;
  createTag: (input: { name: string; color?: string; ledgerId?: string }) => string;
  setTransactionTags: (transactionId: string, tagIds: string[]) => void;
  setTransactionSplits: (transactionId: string, splits: TxSplitInput[]) => void;
  updateTag: (id: string, patch: { name?: string; color?: string | null }) => void;
  deleteTag: (id: string) => void;
  createRule: (input: {
    name?: string | null;
    priority?: number;
    condition: import('@/lib/rules/types').Condition;
    actions: import('@/lib/rules/types').Action[];
    isActive?: boolean;
    runOnEdit?: boolean;
    ledgerId?: string;
  }) => string;
  updateRule: (
    id: string,
    patch: {
      name?: string | null;
      priority?: number;
      condition?: import('@/lib/rules/types').Condition;
      actions?: import('@/lib/rules/types').Action[];
      isActive?: boolean;
      runOnEdit?: boolean;
    },
  ) => void;
  deleteRule: (id: string) => void;
  /** Apply one rule against every confirmed transaction in its ledger. The
   *  server runs the same applyRules path as insertTxRow and persists the
   *  patches via UPDATE / INSERT OR IGNORE; the client gets the fresh
   *  projection back through the normal syncMutation path. */
  backfillRule: (ruleId: string) => void;
  createScheduled: (input: { name: string; description?: string | null; type?: string; amount?: number | null; frequency?: string; dayOfMonth?: number; weekDay?: number; accountId: string; account?: string; fromAccountId?: string; from?: string; autoPost?: boolean; color?: string | null; category?: string | null; startDate?: string; endDate?: string | null; maxExecutions?: number | null; installmentTotal?: number | null; ledgerId?: string }) => string;
  updateScheduled: (id: string, patch: { name?: string; description?: string | null; amount?: number | null; frequency?: string; dayOfMonth?: number; weekDay?: number; autoPost?: number; color?: string | null; category?: string | null; endDate?: string | null; maxExecutions?: number | null; installmentTotal?: number | null }) => void;
  deleteScheduled: (id: string) => void;
  updateTransfer: (id: string, patch: { fromAmount?: number; toAmount?: number; date?: string; time?: string | null; note?: string | null }) => void;
  deleteTransfer: (id: string) => void;
  createCounterparty: (input: { name: string; ledgerId?: string }) => string;
  updateCounterparty: (id: string, patch: { name?: string }) => void;
  deleteCounterparty: (id: string) => void;
  setExchangeRate: (input: { date: string; currency: string; rate: number; source?: string | null }) => void;
  deleteExchangeRate: (date: string, currency: string) => void;
  createHolding: (input: {
    accountId: string;
    symbol: string;
    name?: string | null;
    shares: number;
    costBasis: number;
    currency?: string;
    lastPrice?: number | null;
    lastPriceDate?: string | null;
    notes?: string | null;
    ledgerId?: string;
  }) => string;
  updateHolding: (id: string, patch: { symbol?: string; name?: string | null; shares?: number; costBasis?: number; notes?: string | null }) => void;
  setHoldingPrice: (id: string, price: number | null, date: string | null) => void;
  deleteHolding: (id: string) => void;
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

      setMobileTabIds: (ids) => {
        set({ mobileTabIds: ids });
        syncMutation('setMobileTabIds', { ids });
      },

      setDisplayCurrency: (ledgerId, currency) => {
        set((s) => ({ displayCurrencyByLedger: { ...s.displayCurrencyByLedger, [ledgerId]: currency } }));
        syncMutation('setDisplayCurrency', { ledgerId, currency });
      },

      setBackupFrequency: (frequencyMs) => {
        set((s) => ({ backupConfig: { ...s.backupConfig, frequencyMs } }));
        syncMutation('setBackupFrequency', { frequencyMs });
      },

      setBackupRetention: (retention) => {
        set((s) => ({ backupConfig: { ...s.backupConfig, retention } }));
        syncMutation('setBackupRetention', { retention });
      },

      changeLedgerBase: (ledgerId, newBase) => {
        // The server-side recompute rewrites every locked amount_base in the
        // ledger; the projection that comes back has the new base and the
        // re-derived figures everywhere. Optimistic update flips the local
        // base immediately so the UI doesn't show stale labels.
        set((s) => ({
          ledgers: s.ledgers.map((l) => (l.id === ledgerId ? { ...l, base: newBase } : l)),
        }));
        syncMutation('changeLedgerBase', { ledgerId, newBase });
      },

      createLedger: (input) => {
        // App-side id like every other createX. Server validates non-collision.
        const id = `ledger-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
        const base = input.base.toUpperCase();
        // Optimistic: project the new row with zero counts.
        set((s) => ({
          ledgers: [
            ...s.ledgers,
            {
              id,
              name: input.name,
              base,
              isDefault: 0,
              color: input.color ?? null,
              tagline: input.tagline ?? null,
              accounts: 0,
              txns: 0,
            },
          ],
        }));
        syncMutation('createLedger', {
          id,
          name: input.name,
          base,
          color: input.color ?? null,
          tagline: input.tagline ?? null,
        });
        return id;
      },

      updateLedger: (id, patch) => {
        set((s) => ({
          ledgers: s.ledgers.map((l) => (l.id === id ? { ...l, ...patch } : l)),
        }));
        syncMutation('updateLedger', { id, patch });
      },

      setDefaultLedger: (id) => {
        set((s) => ({
          ledgers: s.ledgers.map((l) => ({ ...l, isDefault: l.id === id ? 1 : 0 })),
        }));
        syncMutation('setDefaultLedger', { id });
      },

      deleteLedger: (id) => {
        // Optimistic: drop the row + every projected slice scoped to this ledger.
        // The server re-projection arrives with the cleaned-up state shortly.
        set((s) => {
          const remaining = s.ledgers.filter((l) => l.id !== id);
          const wasDefault = s.ledgers.find((l) => l.id === id)?.isDefault === 1;
          // Default reassignment: promote first by name when the deleted was default.
          const promoteId = wasDefault
            ? [...remaining].sort((a, b) => a.name.localeCompare(b.name))[0]?.id ?? null
            : null;
          const ledgers = promoteId
            ? remaining.map((l) => ({ ...l, isDefault: l.id === promoteId ? 1 : 0 }))
            : remaining;
          return {
            ledgers,
            accounts: s.accounts.filter((a) => a.ledgerId !== id),
            transactions: s.transactions.filter((t) => (t.ledgerId ?? 'personal') !== id),
            categories: s.categories.filter((c) => c.ledgerId !== id),
            tags: s.tags.filter((t) => t.ledgerId !== id),
            counterparties: s.counterparties.filter((c) => c.ledgerId !== id),
            budgets: s.budgets.filter((b) => b.ledgerId !== id),
            budgetGroups: s.budgetGroups.filter((g) => g.ledgerId !== id),
            accountGroups: s.accountGroups.filter((g) => g.ledgerId !== id),
            scheduled: s.scheduled, // no ledger_id on the projected shape; server filters
            holdings: s.holdings.filter((h) => h.ledgerId !== id),
            rules: s.rules.filter((r) => r.ledgerId !== id),
            attachments: s.attachments.filter((a) => a.ledgerId !== id),
            displayCurrencyByLedger: Object.fromEntries(
              Object.entries(s.displayCurrencyByLedger).filter(([k]) => k !== id),
            ),
          };
        });
        syncMutation('deleteLedger', { id });
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
          kind: tx.kind,
          refundedTransactionId: tx.refundedTransactionId,
          // Optional explicit counterparty link; the server's addTransaction
          // is a thin wrapper around insertTxRow which resolves the link
          // (auto-resolve by name, or accepts an explicit counterpartyId).
          counterpartyId: tx.counterpartyId ?? null,
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

      bulkRecategorize: (ids, categoryId) => {
        if (!ids.length) return;
        const idSet = new Set(ids);
        set((s) => ({
          transactions: s.transactions.map((t) => (idSet.has(t.id) ? { ...t, category: categoryId } : t)),
        }));
        syncMutation('bulkRecategorize', { ids, categoryId });
      },

      setCleared: (transactionId, cleared) => {
        // Optimistic flip. Persist the same ISO timestamp the server would set
        // so the UI's clearedBalance line stays consistent until the projection
        // round-trip overwrites it.
        const stamp = cleared ? new Date().toISOString() : null;
        set((s) => ({
          transactions: s.transactions.map((t) =>
            t.id === transactionId ? { ...t, clearedAt: stamp } : t,
          ),
        }));
        syncMutation('setCleared', { id: transactionId, cleared });
      },

      setReviewed: (transactionId, reviewed) => {
        const stamp = reviewed ? new Date().toISOString() : null;
        set((s) => ({
          transactions: s.transactions.map((t) =>
            t.id === transactionId ? { ...t, reviewedAt: stamp } : t,
          ),
        }));
        syncMutation('setReviewed', { id: transactionId, reviewed });
      },

      markAllReviewed: (ledgerId, opts) => {
        const accountId = opts?.accountId;
        const stamp = new Date().toISOString();
        set((s) => ({
          transactions: s.transactions.map((t) => {
            if ((t.ledgerId ?? 'personal') !== ledgerId) return t;
            if (accountId && t.account !== accountId) return t;
            if (t.pending || t.reviewedAt) return t;
            return { ...t, reviewedAt: stamp };
          }),
        }));
        syncMutation('markAllReviewed', { ledgerId, accountId });
      },

      uploadAttachment: async (transactionId, file) => {
        // Upload bypasses syncMutation (multipart body, not JSON). The route
        // returns the same ProjectedState shape, so adoption mirrors the
        // syncMutation path. We let the caller catch errors so the UI can
        // surface them (size cap, mime allowlist, etc.).
        const { uploadAttachment } = await import('@/lib/api-client');
        const state = await uploadAttachment(transactionId, file);
        useFinanceStore.setState(state);
        // The new row is the most recent one for this transaction.
        const created = [...state.attachments]
          .filter((a) => a.transactionId === transactionId)
          .sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1))[0];
        return created?.id ?? '';
      },

      removeAttachment: (id) => {
        // Optimistic — drop the projected row immediately; the server
        // round-trip overwrites the slice with the authoritative state
        // (and unlinks the file).
        set((s) => ({ attachments: s.attachments.filter((a) => a.id !== id) }));
        syncMutation('removeAttachment', { id });
      },

      reconcileAccount: ({ accountId, statementBalance, statementDate, postAdjustment }) => {
        // Optimistic checkpoint stamp; the remainder Adjustment + cleared
        // flips on it arrive on the round-trip (we don't try to mirror the
        // SUM-and-post logic client-side — it's all in the server case).
        set((s) => ({
          accounts: s.accounts.map((a) =>
            a.id === accountId
              ? { ...a, lastReconciledAt: statementDate, lastReconciledBalance: statementBalance }
              : a,
          ),
        }));
        syncMutation('reconcileAccount', { accountId, statementBalance, statementDate, postAdjustment });
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

      confirmPendingWithMatch: (id, resolution) => {
        // Optimistically flip status. The server-side `confirmPendingWithMerchant`
        // mutation handles status flip + counterparty link + description rewrite
        // in a single UPDATE. We patch the local row's counterpartyId + merchant
        // so the UI doesn't wait for the round-trip to render the canonical name.
        set((s) => ({
          transactions: s.transactions.map((t) => {
            if (t.id !== id) return t;
            // Optimistic preview: if we know the canonical name, surface it
            // immediately. The server re-projects and replaces this with the
            // authoritative row.
            const patched: Tx = { ...t, pending: false };
            if (resolution.kind === 'existing') {
              const cp = useFinanceStore.getState().counterparties.find((c) => c.id === resolution.id);
              if (cp) {
                patched.counterpartyId = cp.id;
                patched.merchant = cp.name;
              } else {
                patched.counterpartyId = resolution.id;
              }
            } else if (resolution.kind === 'new') {
              // Don't fabricate an id — leave the FK unset optimistically.
              // The server creates the counterparty and the projected state
              // surfaces the link.
              patched.merchant = resolution.name;
            }
            return patched;
          }),
        }));
        syncMutation('confirmPendingWithMerchant', {
          id,
          counterpartyId: resolution.kind === 'existing' ? resolution.id : null,
          newCounterpartyName: resolution.kind === 'new' ? resolution.name : null,
        });
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

      unarchiveAccount: (id) => {
        syncMutation('unarchiveAccount', { id });
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

      addScheduledSplit: (templateId, accountId, account, pct) => {
        set((s) => ({
          scheduled: s.scheduled.map((t) =>
            t.id === templateId ? { ...t, splits: [...(t.splits ?? []), { accountId, account, pct, abs: null, label: '' }] } : t,
          ),
        }));
        syncMutation('addScheduledSplit', { templateId, accountId, pct });
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
        const parentId = input.parentId ?? null;
        set((s) => ({ categories: [...s.categories, { id, ledgerId, parentId, name: input.name, type, icon, color }] }));
        syncMutation('createCategory', { ledgerId, parentId, name: input.name, type, icon, color });
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

      createRule: (input) => {
        const id = `rule-${Date.now().toString(36)}`;
        const ledgerId = input.ledgerId ?? 'personal';
        const optimistic: Rule = {
          id,
          ledgerId,
          name: input.name ?? null,
          priority: input.priority ?? 100,
          condition: input.condition,
          actions: input.actions,
          isActive: input.isActive !== false,
          runOnEdit: input.runOnEdit === true,
          lastAppliedAt: null,
        };
        set((s) => ({ rules: [...s.rules, optimistic] }));
        syncMutation('createRule', {
          id,
          ledgerId,
          name: input.name ?? null,
          priority: optimistic.priority,
          condition: input.condition,
          actions: input.actions,
          isActive: optimistic.isActive,
          runOnEdit: optimistic.runOnEdit,
        });
        return id;
      },

      updateRule: (id, patch) => {
        set((s) => ({
          rules: s.rules.map((r) => (r.id === id ? { ...r, ...patch, name: patch.name ?? r.name } : r)),
        }));
        syncMutation('updateRule', { id, patch });
      },

      deleteRule: (id) => {
        set((s) => ({ rules: s.rules.filter((r) => r.id !== id) }));
        syncMutation('deleteRule', { id });
      },

      backfillRule: (id) => {
        // No optimistic update — the server re-projection lands the patched
        // transactions + the rule's new last_applied_at on the round-trip.
        syncMutation('backfillRule', { id });
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
        const description = input.description ?? null;
        const accountId = input.accountId;
        const account = input.account ?? '';
        const fromAccountId = input.fromAccountId;
        const category = input.category ?? null;
        const startDate = input.startDate ?? '';
        const endDate = input.endDate ?? null;
        const maxExecutions = input.maxExecutions ?? null;
        const installmentTotal = input.installmentTotal ?? null;
        set((s) => ({
          scheduled: [
            ...s.scheduled,
            { id, name: input.name, description, type, amount, frequency, dayOfMonth, weekDay, accountId, account, fromAccountId, from: input.from, autoPost, nextRun: '', lastRun: '', color, category, startDate, endDate, maxExecutions, installmentTotal, installmentPaid: 0 },
          ],
        }));
        syncMutation('createScheduled', { id, ledgerId, name: input.name, description, type, amount, frequency, dayOfMonth, weekDay: weekDay ?? null, accountId, fromAccountId: fromAccountId ?? null, autoPost: !!input.autoPost, color, category, startDate, endDate, maxExecutions, installmentTotal });
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

      // Investment positions live on the server in `holdings`; the store mirrors
      // them with an optimistic update + the projected state once the round-trip
      // returns. Currency defaults to the account's on the server when omitted.
      createHolding: (input) => {
        const id = `h-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
        const symbol = input.symbol.trim().toUpperCase();
        const ledgerId = input.ledgerId ?? 'personal';
        set((s) => ({
          holdings: [
            ...s.holdings,
            {
              id,
              ledgerId,
              accountId: input.accountId,
              symbol,
              name: input.name ?? null,
              shares: input.shares,
              costBasis: input.costBasis,
              currency: input.currency ?? 'USD',
              lastPrice: input.lastPrice ?? null,
              lastPriceDate: input.lastPriceDate ?? null,
              notes: input.notes ?? null,
            },
          ],
        }));
        syncMutation('createHolding', {
          id,
          ledgerId,
          accountId: input.accountId,
          symbol,
          name: input.name ?? null,
          shares: input.shares,
          costBasis: input.costBasis,
          currency: input.currency ?? null,
          lastPrice: input.lastPrice ?? null,
          lastPriceDate: input.lastPriceDate ?? null,
          notes: input.notes ?? null,
        });
        return id;
      },

      updateHolding: (id, patch) => {
        const normalized = patch.symbol == null ? patch : { ...patch, symbol: patch.symbol.trim().toUpperCase() };
        set((s) => ({
          holdings: s.holdings.map((h) => (h.id === id ? { ...h, ...normalized } : h)),
        }));
        syncMutation('updateHolding', { id, patch: normalized });
      },

      setHoldingPrice: (id, price, date) => {
        set((s) => ({
          holdings: s.holdings.map((h) => (h.id === id ? { ...h, lastPrice: price, lastPriceDate: date } : h)),
        }));
        syncMutation('setHoldingPrice', { id, price, date });
      },

      deleteHolding: (id) => {
        set((s) => ({ holdings: s.holdings.filter((h) => h.id !== id) }));
        syncMutation('deleteHolding', { id });
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
