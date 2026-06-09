// lib/db/domain/_args.ts — the central per-action Args map.
//
// This is the wire contract for /api/mutate: each of the 74 action names
// has a typed args shape. The dispatcher in lib/db/mutate.ts (PR 4) and
// the route handler in app/api/mutate/route.ts both consume this type.
//
// All 74 actions. Sourced from each domain's types.ts + the mutation cases
// in lib/db/mutations.ts. The mapping is a one-to-one mirror of those
// cases; any drift surfaces as a tsc error when the dispatcher is added
// in PR 4.

import type { AddInput, TransactionPatch } from './transactions/types';
import type { AccountPatch, NewAccount } from './accounts/types';
import type { AccountGroupPatch, NewAccountGroup } from './accountGroups/types';
import type {
  BudgetCyclePatch,
  BudgetPatch,
  NewBudget,
} from './budgets/types';
import type { BudgetGroupPatch } from './budgetGroups/types';
import type { CategoryPatch } from './categories/types';
import type {
  CounterpartyPatch,
  NewCounterparty,
} from './counterparties/types';
import type { HoldingPatch, NewHolding } from './holdings/types';
import type { LedgerPatch, NewLedgerInput } from './ledgers/types';
import type { RulePatchInput } from './rules/types';
import type { ScheduledPatch } from './scheduled/types';
import type { TagPatch } from './tags/types';
import type { TransferPatch } from './transfers/types';
import type { Action, Condition } from '@/lib/rules/types';

export type Args = {
  // --- transactions (12) ---
  addTransaction: AddInput;
  adjustAccountBalance: {
    accountId: string;
    targetBalance: number;
    date?: string;
    note?: string;
    source?: 'reconcile' | 'manual';
  };
  updateTransaction: { id: string; patch: TransactionPatch };
  setCleared: { id: string; cleared: boolean };
  setReviewed: { id: string; reviewed: boolean };
  markAllReviewed: { ledgerId?: string; accountId?: string };
  reconcileAccount: {
    accountId: string;
    statementBalance: number;
    statementDate?: string;
    postAdjustment?: boolean;
  };
  bulkRecategorize: { ids: string[]; categoryId: string | null };
  deleteTransaction: { id: string };
  removeAttachment: { id: string };
  confirmTransaction: { id: string };
  confirmPendingWithMerchant: {
    id: string;
    counterpartyId?: string | null;
    newCounterpartyName?: string | null;
  };
  setTransactionTags: { id: string; tagIds: string[] };
  setTransactionSplits: {
    id: string;
    splits: { categoryId: string | null; amount: number; description: string | null }[];
  };

  // --- counterparties (5) ---
  confirmAllPending: Record<string, never>;
  createCounterparty: NewCounterparty;
  updateCounterparty: { id: string; patch: CounterpartyPatch };
  deleteCounterparty: { id: string };
  verifyCounterparty: { id: string };
  unverifyCounterparty: { id: string };

  // --- accounts (5) ---
  createAccount: NewAccount;
  updateAccount: { id: string; patch: AccountPatch };
  archiveAccount: { id: string };
  unarchiveAccount: { id: string };
  deleteAccount: { id: string };

  // --- account groups (3) ---
  createAccountGroup: NewAccountGroup;
  updateAccountGroup: { id: string; patch: AccountGroupPatch };
  deleteAccountGroup: { id: string };

  // --- budgets (6) ---
  createBudget: NewBudget & {
    id?: string;
    saved?: number;
    frequency?: string;
    startDate?: string;
    isRecurring?: number;
  };
  updateBudget: { id: string; patch: BudgetPatch };
  updateBudgetCycle: { id: string; patch: BudgetCyclePatch };
  clearPendingAmount: { id: string };
  removeBudget: { id: string };
  contributeBudget: { id: string; amount: number };

  // --- budget groups (3) ---
  createBudgetGroup: { id?: string; ledgerId?: string; name: string };
  updateBudgetGroup: { id: string; patch: BudgetGroupPatch };
  deleteBudgetGroup: { id: string };

  // --- categories (3) ---
  createCategory: {
    name: string;
    ledgerId?: string;
    type?: string;
    icon?: string | null;
    color?: string | null;
    parentId?: string | null;
  };
  updateCategory: { id: string; patch: CategoryPatch };
  deleteCategory: { id: string };

  // --- tags (3) ---
  createTag: { id?: string; ledgerId?: string; name: string; color?: string | null };
  updateTag: { id: string; patch: TagPatch };
  deleteTag: { id: string };

  // --- rules (4) ---
  createRule: {
    id?: string;
    ledgerId?: string;
    name?: string | null;
    priority?: number;
    condition: Condition;
    actions: Action[];
    isActive?: boolean;
    runOnEdit?: boolean;
  };
  updateRule: { id: string; patch: RulePatchInput };
  deleteRule: { id: string };
  backfillRule: { id: string };

  // --- scheduled (7) ---
  createScheduled: {
    id?: string;
    ledgerId?: string;
    name: string;
    description?: string | null;
    type?: string;
    amount?: number | string | null;
    frequency?: string;
    dayOfMonth?: number;
    weekDay?: number | null;
    accountId: string;
    fromAccountId?: string;
    autoPost?: boolean;
    color?: string | null;
    category?: string | null;
    startDate?: string;
    endDate?: string | null;
    maxExecutions?: number | null;
    installmentTotal?: number | string | null;
  };
  updateScheduled: { id: string; patch: ScheduledPatch };
  deleteScheduled: { id: string };
  addScheduledSplit: { templateId: string; accountId: string; pct: number };
  removeScheduledSplit: { templateId: string; index: number };
  updateScheduledSplit: { templateId: string; index: number; pct: number };
  postScheduled: { templateId: string };
  generateDueScheduled: { today?: string };

  // --- transfers (3) ---
  createTransfer: {
    fromAccountId: string;
    toAccountId: string;
    fromAmount: number;
    toAmount?: number;
    date: string;
    time?: string;
    note?: string | null;
    sourceTemplateId?: string;
  };
  updateTransfer: { id: string; patch: TransferPatch };
  deleteTransfer: { id: string };

  // --- holdings (4) ---
  createHolding: NewHolding;
  updateHolding: { id: string; patch: HoldingPatch };
  setHoldingPrice: { id: string; price: number | null; date?: string | null };
  deleteHolding: { id: string };

  // --- ledgers (5) ---
  createLedger: NewLedgerInput;
  updateLedger: {
    id: string;
    patch: LedgerPatch;
  };
  setDefaultLedger: { id: string };
  deleteLedger: { id: string };
  changeLedgerBase: { ledgerId: string; newBase: string };

  // --- system (2) ---
  setExchangeRate: { date: string; currency: string; rate: number; source?: string };
  deleteExchangeRate: { date: string; currency: string };

  // --- app_state (5) ---
  setMobileTabIds: { ids: string[] };
  setDisplayCurrency: { ledgerId: string; currency: string };
  setBackupFrequency: { frequencyMs: number };
  setBackupRetention: { retention: number };
  reset: Record<string, never>;
};

export type ActionName = keyof Args;

/** Helper: the args for a specific action. Use this in the dispatcher
 *  (PR 4) to constrain the per-case switch. */
export type ArgsFor<A extends ActionName> = Args[A];
