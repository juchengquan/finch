// Read + admin operations on the ledgers table.
//
// The ledger base currency is mutable via `recomputeAmountBases`: changing
// the base forces a full rewrite of every locked `amount_base` (transactions,
// transaction_splits) under the new base + locked rate per transaction date.
// Account current balances are then re-derived from opening + Σ deltas.

import type { Exec } from '@/lib/db/repo';
import { convertToBase } from './rates';
import { recomputeAccount } from './accounts';

export interface LedgerRow {
  id: string;
  name: string;
  base: string;
  isDefault: number;
}

/** List ledgers — projected so the UI can react when one's base flips. */
export async function listLedgers(exec: Exec): Promise<LedgerRow[]> {
  const rows = await exec(
    'SELECT id, name, base_currency AS base, is_default AS isDefault FROM ledgers ORDER BY is_default DESC, name',
  );
  return rows.map((r) => ({
    id: String(r.id),
    name: String(r.name),
    base: String(r.base),
    isDefault: Number(r.isDefault),
  }));
}

/**
 * Rewrite every locked `amount_base` in `ledgerId` against `newBase` using each
 * transaction's date + native currency to look up rates. Updates:
 *   - ledgers.base_currency to newBase
 *   - transactions.amount_base + exchange_rate
 *   - transaction_splits.amount_base (per-split, same conversion logic)
 *   - accounts.current_balance via recomputeAccount (because cross-currency
 *     rows now produce different account-currency deltas after the rebuild)
 *
 * Idempotent: running with the current base is a no-op (each row reconverts
 * to the same figure). Wrapped in BEGIN/COMMIT so a mid-run failure leaves
 * the ledger in its pre-call state.
 */
export async function recomputeAmountBases(
  exec: Exec,
  ledgerId: string,
  newBase: string,
): Promise<{ transactions: number; splits: number; accounts: number }> {
  await exec('BEGIN');
  try {
    await exec(
      "UPDATE ledgers SET base_currency = ?, updated_at = datetime('now') WHERE id = ?",
      [newBase, ledgerId],
    );

    const txns = await exec(
      'SELECT id, date, currency, amount FROM transactions WHERE ledger_id = ?',
      [ledgerId],
    );
    for (const t of txns) {
      const conv = await convertToBase(
        exec,
        Number(t.amount),
        String(t.currency),
        newBase,
        String(t.date),
      );
      await exec(
        "UPDATE transactions SET amount_base = ?, exchange_rate = ?, updated_at = datetime('now') WHERE id = ?",
        [conv.amountBase, conv.rate, String(t.id)],
      );
    }

    // Splits carry their own amount_base in the ledger base. Native amount and
    // currency follow the parent's, so the same convertToBase applies.
    const splits = await exec(
      `SELECT ts.id, ts.amount, t.currency, t.date
         FROM transaction_splits ts JOIN transactions t ON t.id = ts.transaction_id
        WHERE t.ledger_id = ?`,
      [ledgerId],
    );
    for (const s of splits) {
      const conv = await convertToBase(
        exec,
        Number(s.amount),
        String(s.currency),
        newBase,
        String(s.date),
      );
      await exec(
        'UPDATE transaction_splits SET amount_base = ? WHERE id = ?',
        [conv.amountBase, String(s.id)],
      );
    }

    // Account balances are stored in each account's own currency, but the
    // trigger's choice of delta (native vs amount_base) depends on whether
    // the txn currency matches the account currency. Foreign rows on
    // account-currency-matches-old-base accounts changed meaning, so rebuild.
    // The locked opening_balance_base must also move to the new base — same
    // creation-date rate, just expressed against newBase via the USD pivot.
    const accts = await exec(
      'SELECT id, currency, opening_balance, created_at FROM accounts WHERE ledger_id = ?',
      [ledgerId],
    );
    for (const a of accts) {
      const createdDate = String(a.created_at ?? '').slice(0, 10);
      const conv = await convertToBase(
        exec,
        Number(a.opening_balance ?? 0),
        String(a.currency),
        newBase,
        createdDate,
      );
      await exec(
        "UPDATE accounts SET opening_balance_base = ?, updated_at = datetime('now') WHERE id = ?",
        [conv.amountBase, String(a.id)],
      );
      await recomputeAccount(exec, String(a.id));
    }

    await exec('COMMIT');
    return { transactions: txns.length, splits: splits.length, accounts: accts.length };
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}
