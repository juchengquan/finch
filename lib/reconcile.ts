// Reconcile-to-statement math. Pure function over the projected store —
// mirrors recomputeAccount's currency handling so the cleared-balance figure
// matches what the account-detail balance card shows.
//
// See plans/RECONCILE_PLAN.md §3.

import type { Tx } from '@/lib/store';
import type { AccountRow } from '@/lib/db/queries/accounts';

export interface ReconcileState {
  /** Cleared (opening + ticked-confirmed) balance in account currency. */
  clearedBalance: number;
  /** Target the user typed (statement ending balance), account currency. */
  statementBalance: number;
  /** statementBalance - clearedBalance. Zero = reconciled. */
  difference: number;
  /** Cleared confirmed rows touching this account. */
  clearedCount: number;
  /** Uncleared confirmed rows touching this account (the ticking work). */
  unclearedCount: number;
  /** True when |difference| < 0.005 (penny tolerance, dodges float noise). */
  balanced: boolean;
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Compute the live reconcile state for an account against a statement target.
 *
 * `clearedBalance` walks the account from its `opening_balance` and adds every
 * **confirmed, cleared** transaction touching this account — in the account's
 * native currency when the row was already denominated in it, else the
 * ledger-base figure (mirrors `recomputeAccount` in queries/accounts.ts so the
 * arithmetic matches `current_balance` for an account where every row is
 * cleared). Pending rows never count — they're not on a statement yet.
 *
 * `txns` is expected to be the projected transaction list (Tx[] from the
 * store). The function filters by account internally; callers can pass the
 * full ledger list.
 */
export function reconcileState(
  account: AccountRow,
  txns: Tx[],
  statementBalance: number,
): ReconcileState {
  let running = Number(account.openingBalance);
  let clearedCount = 0;
  let unclearedCount = 0;

  for (const t of txns) {
    if (t.account !== account.id) continue;
    if (t.pending) continue;
    if (t.clearedAt) {
      // Mirrors recomputeAccount: native amount when the row is already in the
      // account currency, else the ledger-base figure.
      const delta = (t.currency ?? account.currency) === account.currency
        ? (t.nativeAmount ?? t.amount)
        : t.amount;
      running = r2(running + delta);
      clearedCount++;
    } else {
      unclearedCount++;
    }
  }

  const clearedBalance = r2(running);
  const difference = r2(statementBalance - clearedBalance);
  return {
    clearedBalance,
    statementBalance: r2(statementBalance),
    difference,
    clearedCount,
    unclearedCount,
    balanced: Math.abs(difference) < 0.005,
  };
}
