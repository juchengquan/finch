// Transfers derived from the transactions table: each transfer_group_id has an
// outgoing row (amount < 0) and an incoming row (amount > 0). We reconstruct the
// from/to accounts and amount by grouping on transfer_group_id.

import type { Exec } from '@/lib/db/repo';
import { recomputeAccount } from './accounts';

export interface Transfer {
  id: string; // transfer_group_id
  date: string;
  amount: number; // positive magnitude sent, in `fromCurrency` (native)
  toAmount: number; // positive magnitude received, in `toCurrency` (native)
  fromCurrency: string;
  toCurrency: string;
  fromAccountId: string | null;
  toAccountId: string | null;
  fromName: string | null;
  toName: string | null;
  note: string | null;
}

export async function listTransfers(exec: Exec, ledgerId: string): Promise<Transfer[]> {
  const rows = await exec(
    `SELECT
       t.transfer_group_id AS id,
       MAX(t.date) AS date,
       MAX(CASE WHEN t.amount < 0 THEN -t.amount END) AS amount,
       MAX(CASE WHEN t.amount > 0 THEN t.amount END) AS toAmount,
       MAX(CASE WHEN t.amount < 0 THEN t.currency END) AS fromCurrency,
       MAX(CASE WHEN t.amount > 0 THEN t.currency END) AS toCurrency,
       MAX(CASE WHEN t.amount < 0 THEN t.account_id END) AS fromId,
       MAX(CASE WHEN t.amount > 0 THEN t.account_id END) AS toId,
       MAX(t.notes) AS note
     FROM transactions t
     WHERE t.ledger_id = ? AND t.transfer_group_id IS NOT NULL
     GROUP BY t.transfer_group_id
     ORDER BY date DESC`,
    [ledgerId],
  );
  if (rows.length === 0) return [];

  const accts = await exec('SELECT id, name FROM accounts WHERE ledger_id = ?', [ledgerId]);
  const nameById = new Map(accts.map((a) => [String(a.id), String(a.name)]));
  return rows.map((r) => ({
    id: String(r.id),
    date: String(r.date),
    amount: Number(r.amount ?? 0),
    toAmount: Number(r.toAmount ?? 0),
    fromCurrency: r.fromCurrency == null ? 'USD' : String(r.fromCurrency),
    toCurrency: r.toCurrency == null ? 'USD' : String(r.toCurrency),
    fromAccountId: r.fromId == null ? null : String(r.fromId),
    toAccountId: r.toId == null ? null : String(r.toId),
    fromName: r.fromId == null ? null : nameById.get(String(r.fromId)) ?? null,
    toName: r.toId == null ? null : nameById.get(String(r.toId)) ?? null,
    note: r.note == null ? null : String(r.note),
  }));
}

export interface TransferPatch {
  /** Sent magnitude, in the from-account's currency. */
  fromAmount?: number;
  /** Received magnitude, in the to-account's currency. Set this when the
   *  bank's actual conversion differs from the mid-rate; the effective FX
   *  rate becomes `toAmount / fromAmount`. */
  toAmount?: number;
  date?: string;
  note?: string | null;
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Edit a transfer in place. The two amounts can move independently:
 *   - only `fromAmount`: scale the to-leg proportionally (preserve FX ratio)
 *   - only `toAmount`:   scale the from-leg proportionally (preserve FX ratio)
 *   - both:              write each leg exactly as given; on cross-currency
 *                        transfers the stored exchange_rate is recomputed
 *                        from the new ratio.
 * Same-currency transfers must end with equal magnitudes (validated when both
 * are set). Recomputes both accounts after the rewrite.
 */
export async function updateTransfer(exec: Exec, groupId: string, patch: TransferPatch): Promise<void> {
  const legs = await exec(
    'SELECT id, account_id, amount, amount_base FROM transactions WHERE transfer_group_id = ?',
    [groupId],
  );
  if (!legs.length) return;

  const fromLeg = legs.find((l) => Number(l.amount) < 0) ?? legs[0];
  const toLeg = legs.find((l) => Number(l.amount) > 0) ?? legs[legs.length - 1];
  const [tg] = await exec('SELECT from_currency, to_currency FROM transfer_groups WHERE id = ?', [groupId]);
  const sameCurrency = tg && String(tg.from_currency) === String(tg.to_currency);

  const hasFrom = patch.fromAmount !== undefined;
  const hasTo = patch.toAmount !== undefined;

  if (hasFrom || hasTo) {
    const oldFrom = Math.abs(Number(fromLeg.amount));
    const oldTo = Math.abs(Number(toLeg.amount));
    let newFrom = hasFrom ? Math.abs(Number(patch.fromAmount)) : oldFrom;
    let newTo = hasTo ? Math.abs(Number(patch.toAmount)) : oldTo;

    if (!(newFrom > 0)) throw new Error('Transfer amount must be greater than 0');
    if (!(newTo > 0)) throw new Error('Transfer amount must be greater than 0');

    if (hasFrom && !hasTo) {
      // Preserve ratio: scale to-leg by the same factor as from-leg.
      const factor = oldFrom > 0 ? newFrom / oldFrom : 1;
      newTo = r2(oldTo * factor);
    } else if (hasTo && !hasFrom) {
      const factor = oldTo > 0 ? newTo / oldTo : 1;
      newFrom = r2(oldFrom * factor);
    } else if (sameCurrency && Math.abs(newFrom - newTo) > 0.005) {
      throw new Error('Same-currency transfer amounts must match');
    }

    // amount_base on each leg keeps the same scale relative to its leg's native
    // amount. amount_base on the transfer_group reflects the from-side magnitude.
    const scaleFrom = oldFrom > 0 ? newFrom / oldFrom : 1;
    const scaleTo = oldTo > 0 ? newTo / oldTo : 1;
    await exec('UPDATE transactions SET amount = ?, amount_base = ? WHERE id = ?', [
      -r2(newFrom),
      r2(Number(fromLeg.amount_base) * scaleFrom),
      String(fromLeg.id),
    ]);
    await exec('UPDATE transactions SET amount = ?, amount_base = ? WHERE id = ?', [
      r2(newTo),
      r2(Number(toLeg.amount_base) * scaleTo),
      String(toLeg.id),
    ]);

    const newRate = sameCurrency ? 1 : r2(newTo / newFrom * 1e6) / 1e6;
    await exec('UPDATE transfer_groups SET amount_base = ?, exchange_rate = ? WHERE id = ?', [
      r2(newFrom),
      newRate,
      groupId,
    ]);
  }
  if (patch.date !== undefined) {
    await exec('UPDATE transactions SET date = ? WHERE transfer_group_id = ?', [patch.date, groupId]);
  }
  if (patch.note !== undefined) {
    await exec('UPDATE transactions SET notes = ? WHERE transfer_group_id = ?', [patch.note ?? null, groupId]);
    await exec('UPDATE transfer_groups SET notes = ? WHERE id = ?', [patch.note ?? null, groupId]);
  }

  for (const r of new Set(legs.map((l) => String(l.account_id)))) {
    await recomputeAccount(exec, r);
  }
}

/**
 * Delete a transfer: remove both leg transactions and the group row, then
 * recompute the balances of the affected accounts (the balance trigger only
 * fires on INSERT, so removing rows needs an explicit recompute).
 */
export async function deleteTransfer(exec: Exec, groupId: string): Promise<void> {
  const legs = await exec('SELECT DISTINCT account_id FROM transactions WHERE transfer_group_id = ?', [groupId]);
  await exec('DELETE FROM transactions WHERE transfer_group_id = ?', [groupId]);
  await exec('DELETE FROM transfer_groups WHERE id = ?', [groupId]);
  for (const r of legs) await recomputeAccount(exec, String(r.account_id));
}
