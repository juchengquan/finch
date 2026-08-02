// frontend/lib/store/transactions/state.ts — transactions-domain slice of
// the initial state. Pure data; the action creators (added in Task 4)
// live in transactions/actions.ts. `attachments` is part of the
// transactions slice (they're projected off transactions, not their own
// domain). The `scheduled` array lives in scheduled/state.ts; `transfers`
// don't own a state slice (they're two transaction rows sharing a
// `transferGroupId`).
//
// Also owns the data-type definitions (Tx, TxSplit, TxSplitInput) that
// were previously declared in lib/store.ts:11-68. They live here (the
// transactions domain's state file) because every consumer of these types
// is the transactions domain or its consumers. Re-exported from
// lib/store/index.ts so the existing `import type { Tx } from '@/lib/store'`
// paths keep working during the migration.

import type { Attachment } from '@/lib/db/domain/attachments/types';

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
  /** Number of account legs on this Tx's entry (>= 1). A split purchase has
   *  several — enrichLegTxs already computes this to derive transferGroupId;
   *  exposed so callers (e.g. the delete-confirmation dialog) don't have to
   *  re-query it. */
  accountLegCount?: number;
  /** The `entries.id` this posting belongs to — stamped on EVERY row, so
   *  grouping by it always reconstructs the purchase. `Tx.id` is the POSTING
   *  id, so a purchase paid from several accounts is several rows, and anything
   *  counting rows counts it more than once. Optional only because fixtures
   *  written before this field existed decode without it. */
  entryId?: string;
  /** The scheduled template this row was auto-generated from (if any). */
  sourceTemplateId?: string;
  /** The scheduled occurrence this row fulfils (`entries.occurrence_date`).
   *  Undefined on rows written before this column existed, and on any entry
   *  not linked to a schedule — callers resolving `sourceTemplateId|date`
   *  keys must fall back to `date` in that case, so no backfill is required. */
  occurrenceDate?: string;
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

export const transactionsInitial = {
  transactions: [] as Tx[],
  attachments: [] as Attachment[],
} as const;
