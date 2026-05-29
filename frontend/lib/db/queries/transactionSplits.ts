// Ad-hoc category splits for one transaction. When a tx has rows here, the
// splits override the parent's category in aggregations (categorySpend,
// monthlyByCategory, budgetProgress). Splits must sum to the parent's
// amount/amount_base — enforced at the mutation boundary.

import type { Exec } from '@/lib/db/repo';

export interface TxSplitRow {
  id: string;
  transactionId: string;
  categoryId: string | null;
  amount: number;
  amountBase: number;
  description: string | null;
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/** Load all splits for a list of transaction ids, keyed by transaction_id. */
export async function splitsByTransaction(exec: Exec, txnIds: string[]): Promise<Map<string, TxSplitRow[]>> {
  const out = new Map<string, TxSplitRow[]>();
  if (txnIds.length === 0) return out;
  const placeholders = txnIds.map(() => '?').join(',');
  const rows = await exec(
    `SELECT id, transaction_id, category_id, amount, amount_base, description
       FROM transaction_splits
      WHERE transaction_id IN (${placeholders})
      ORDER BY sort_order`,
    txnIds,
  );
  for (const r of rows) {
    const txId = String(r.transaction_id);
    const arr = out.get(txId) ?? [];
    arr.push({
      id: String(r.id),
      transactionId: txId,
      categoryId: r.category_id == null ? null : String(r.category_id),
      amount: Number(r.amount),
      amountBase: Number(r.amount_base),
      description: r.description == null ? null : String(r.description),
    });
    out.set(txId, arr);
  }
  return out;
}

export interface NewSplitInput {
  categoryId: string | null;
  amount: number; // signed, native (tx currency)
  description?: string | null;
}

/**
 * Replace all splits for one transaction. amount_base is derived per split as
 * `split.amount * (parent.amount_base / parent.amount)` so same-currency txns
 * map 1:1 and FX txns preserve the parent's locked rate. Splits must sum to
 * the parent's amount within 2 dp; passing `[]` clears all splits.
 */
export async function setTransactionSplits(
  exec: Exec,
  transactionId: string,
  splits: NewSplitInput[],
): Promise<void> {
  const [parent] = await exec(
    'SELECT amount, amount_base FROM transactions WHERE id = ?',
    [transactionId],
  );
  if (!parent) throw new Error('Transaction not found');
  await exec('DELETE FROM transaction_splits WHERE transaction_id = ?', [transactionId]);
  if (splits.length === 0) return;
  if (splits.length < 2) throw new Error('Splits need at least two rows (or pass an empty list to clear)');
  const total = splits.reduce((s, x) => s + x.amount, 0);
  if (Math.abs(r2(total) - r2(Number(parent.amount))) > 0.005) {
    throw new Error(`Splits must sum to the transaction amount (got ${r2(total)}, need ${r2(Number(parent.amount))})`);
  }
  const ratio = Number(parent.amount) !== 0 ? Number(parent.amount_base) / Number(parent.amount) : 1;
  for (let i = 0; i < splits.length; i++) {
    const s = splits[i];
    const id = `${transactionId}-s-${Date.now().toString(36)}-${i}`;
    const amountBase = r2(s.amount * ratio);
    await exec(
      `INSERT INTO transaction_splits (id, transaction_id, category_id, amount, amount_base, description, sort_order)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, transactionId, s.categoryId, s.amount, amountBase, s.description ?? null, i],
    );
  }
}
