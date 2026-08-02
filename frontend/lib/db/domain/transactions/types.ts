// lib/db/domain/transactions/types.ts — public row + input/patch shapes for
// the transactions domain. Keep this file free of SQL imports — it should be
// safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

import type { Tx } from '@/lib/store';

export type Direction = 'all' | 'in' | 'out';

export interface ListOptions {
  ledgerId: string;
  direction?: Direction;
  query?: string;
  accountId?: string;
  categoryId?: string;
  status?: 'pending' | 'confirmed';
  from?: string; // inclusive YYYY-MM-DD
  to?: string; // inclusive YYYY-MM-DD
  /** Filter by absolute amount, magnitude in the ledger base currency. */
  minAmount?: number;
  maxAmount?: number;
  limit?: number;
  offset?: number;
}

export interface AddInput {
  ledgerId: string;
  /** Single-account form. Optional only because `accounts` may carry the
   *  payment sources instead; exactly one of the two must be present. */
  accountId?: string;
  /** Split tender: the same purchase paid from several accounts. Each
   *  share's `amount` is in that account's own currency and they must
   *  total `amount`. Mirrors iOS's `AddInput.AccountShare`. */
  accounts?: { accountId: string; amount: number }[];
  amount: number; // signed, native (in `currency`)
  amountBase?: number; // signed, ledger base; defaults to `amount` (same-currency)
  currency?: string; // native currency; defaults to the account's currency
  merchant: string;
  categoryId?: string | null;
  date: string;
  time?: string;
  note?: string;
  status?: 'pending' | 'confirmed';
  /** Explicit classification; defaults to income/expense by amount sign.
   *  'adjustment' is the manual balance-reconciliation kind; 'refund' is a
   *  positive row that nets against its category (see refundedTransactionId). */
  kind?: 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund';
  /** For kind='refund': the original expense this refund offsets. */
  refundedTransactionId?: string | null;
  /** Optional explicit counterparty link. When provided, the wrapper
   *  forwards it to `insertTxRow`, which uses it as the FK and skips the
   *  name-based auto-resolve. The projection in `state.ts` still overwrites
   *  `merchant` with the canonical counterparty name on read. */
  counterpartyId?: string | null;
  /** Bypass the rules engine for this insert. */
  skipRules?: boolean;
  /** Links this entry to the scheduled template it fulfils (posting a
   *  scheduled occurrence through the normal add-transaction flow). Optional
   *  — omitted/undefined behaves exactly as before. */
  sourceTemplateId?: string | null;
  /** The scheduled occurrence this entry fulfils (yyyy-MM-dd), when posted
   *  from a template via sourceTemplateId. Optional, no behaviour change when
   *  absent. */
  occurrenceDate?: string | null;
}

export interface NewTxRow {
  ledgerId: string;
  accountId: string;
  date: string;
  time?: string | null;
  /** Signed native amount in `currency` (the account's currency). */
  amount: number;
  description: string;
  kind: 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund';
  /** Optional: omit to default to the account's own currency. */
  currency?: string;
  categoryId?: string | null;
  status?: 'pending' | 'confirmed';
  transferGroupId?: string | null;
  refundedTransactionId?: string | null;
  sourceTemplateId?: string | null;
  notes?: string | null;
  /** Pre-resolved (amount_base, rate) when the caller already has them
   *  (seed already converted the whole batch; recompute paths supply
   *  their own). Default: convert on the fly via `convertToBase`. */
  amountBase?: number;
  exchangeRate?: number;
  /** Pre-resolved counterparty id. Pass `null` to skip the lookup with a
   *  known-empty result; omit (undefined) to run the resolver. */
  counterpartyId?: string | null;
  /** Override the generated id (seed uses fixed ids). */
  id?: string;
  /** Override created/updated/confirmed timestamps (seed uses SEED_TS). */
  timestamp?: string;
  /** Bypass the rules engine for this insert. Used by seed (rules don't exist
   *  during seeding) and as an escape hatch for rule-generated rows that must
   *  not re-trigger rules (the infinite-loop guard). Default false. */
  skipRules?: boolean;
}

/**
 * Server-side patch shape. Mirrors the in-app `Tx` columns that are editable
 * via the edit-transaction sheet, plus three server-only fields the client
 * shape doesn't carry:
 *
 *   - `account`   — change the account FK. The OLD account is returned via
 *     `oldAccountId` so the dispatcher can recompute it (the row no longer
 *     contributes to its balance). Cross-ledger moves are rejected.
 *   - `currency`  — change the row's native currency. The form's `amount`
 *     stays as the user entered it; amount_base + exchange_rate are re-derived
 *     against the new currency at the (possibly edited) date. A `date`-only
 *     edit re-derives them too — the locked rate must always be the rate on
 *     the row's own date.
 *   - `status`    — flip pending ↔ confirmed. `confirmed_at` follows the flip
 *     (now on confirm, NULL on demote). The recompute step picks up the
 *     change in the account balance, since the balance sum is `confirmed`-only.
 */
export interface TransactionPatch {
  merchant?: Tx['merchant'];
  category?: Tx['category'];
  amount?: Tx['amount'];
  date?: Tx['date'];
  time?: Tx['time'];
  note?: Tx['note'];
  kind?: Tx['kind'];
  refundedTransactionId?: Tx['refundedTransactionId'];
  account?: string;
  currency?: string;
  status?: 'pending' | 'confirmed';
}
