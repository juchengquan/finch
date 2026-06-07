// Transfers derived from entries: each transfer entry has two account legs
// (from = negative amount, to = positive amount). We reconstruct the from/to
// accounts and amounts from the postings. Write paths delegate to rebuildEntry
// and deleteEntry (DOUBLE_ENTRY_PLAN §6).

import type { Exec } from '@/lib/db/repo';
import { rebuildEntry, deleteEntry, resolveEntryRef } from '@/lib/db/entries';
import { I18nError } from '@/lib/i18n-error';

export interface Transfer {
  id: string; // entry id (was transfer_group_id)
  date: string;
  /** Time-of-day "HH:MM" shared by both legs; null when none was recorded. */
  time: string | null;
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

// B4: read path (listTransfers) is rewritten to query entries+postings.
// For now the read path keeps its legacy SQL body — it's intentionally left
// unedited (B4's scope).
export async function listTransfers(exec: Exec, ledgerId: string): Promise<Transfer[]> {
  const rows = await exec(
    `SELECT
       t.transfer_group_id AS id,
       MAX(t.date) AS date,
       MAX(t.time) AS time,
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
    time: r.time == null ? null : String(r.time),
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
  /** Time-of-day "HH:MM" written to both legs; null clears it. */
  time?: string | null;
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
 * are set). Preserves pinned rates: new amountBase = oldBase × (newNative/oldNative).
 * Recomputes both accounts after the rewrite.
 */
export async function updateTransfer(exec: Exec, groupId: string, patch: TransferPatch): Promise<void> {
  // Resolve the groupId (may be an entry id or a posting id).
  const ref = await resolveEntryRef(exec, groupId);
  if (!ref) return;
  const entryId = ref.entryId;

  // Load current entry + postings.
  const [entry] = await exec('SELECT date, time, notes FROM entries WHERE id = ?', [entryId]);
  if (!entry) return;

  const postings = await exec(
    'SELECT id, account_id, amount, amount_base, exchange_rate, currency, cleared_at, memo FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order',
    [entryId],
  );
  if (postings.length < 2) return;

  const fromLeg = postings.find((l) => Number(l.amount) < 0) ?? postings[0];
  const toLeg = postings.find((l) => Number(l.amount) > 0) ?? postings[postings.length - 1];
  const fromCurrency = String(fromLeg.currency);
  const toCurrency = String(toLeg.currency);
  const sameCurrency = fromCurrency === toCurrency;

  const hasFrom = patch.fromAmount !== undefined;
  const hasTo = patch.toAmount !== undefined;

  let newFromNative = Math.abs(Number(fromLeg.amount));
  let newToNative = Math.abs(Number(toLeg.amount));

  if (hasFrom || hasTo) {
    const oldFrom = Math.abs(Number(fromLeg.amount));
    const oldTo = Math.abs(Number(toLeg.amount));

    if (hasFrom) newFromNative = Math.abs(Number(patch.fromAmount));
    if (hasTo) newToNative = Math.abs(Number(patch.toAmount));

    if (!(newFromNative > 0)) throw new I18nError('error.transfer.amountGt0', {}, 'Transfer amount must be greater than 0');
    if (!(newToNative > 0)) throw new I18nError('error.transfer.amountGt0', {}, 'Transfer amount must be greater than 0');

    if (hasFrom && !hasTo) {
      // Preserve ratio: scale to-leg by the same factor as from-leg.
      const factor = oldFrom > 0 ? newFromNative / oldFrom : 1;
      newToNative = r2(oldTo * factor);
    } else if (hasTo && !hasFrom) {
      const factor = oldTo > 0 ? newToNative / oldTo : 1;
      newFromNative = r2(oldFrom * factor);
    } else if (sameCurrency && Math.abs(newFromNative - newToNative) > 0.005) {
      throw new I18nError('error.transfer.sameCurrencyMismatch', {}, 'Same-currency transfer amounts must match');
    }

    // Preserve pinned rates: new base = old base × (new native / old native).
    const oldFromBase = Math.abs(Number(fromLeg.amount_base));
    const oldToBase = Math.abs(Number(toLeg.amount_base));
    const oldFrom2 = Math.abs(Number(fromLeg.amount));
    const oldTo2 = Math.abs(Number(toLeg.amount));
    const scaleFrom = oldFrom2 > 0 ? newFromNative / oldFrom2 : 1;
    const scaleTo = oldTo2 > 0 ? newToNative / oldTo2 : 1;
    const newFromBase = r2(oldFromBase * scaleFrom);
    const newToBase = r2(oldToBase * scaleTo);
    const newFromRate = newFromNative !== 0 ? Math.round((newFromBase / newFromNative) * 1e6) / 1e6 : Number(fromLeg.exchange_rate);
    const newToRate = newToNative !== 0 ? Math.round((newToBase / newToNative) * 1e6) / 1e6 : Number(toLeg.exchange_rate);

    // Build legs with explicitly resolved bases (no re-lock from rates table).
    const entryPatch: import('@/lib/db/entries').EntryPatch = {
      legs: [
        {
          id: String(fromLeg.id),
          accountId: String(fromLeg.account_id),
          amount: -newFromNative,
          amountBase: -newFromBase,
          exchangeRate: newFromRate,
          clearedAt: fromLeg.cleared_at == null ? null : String(fromLeg.cleared_at),
          memo: fromLeg.memo == null ? null : String(fromLeg.memo),
        },
        {
          id: String(toLeg.id),
          accountId: String(toLeg.account_id),
          amount: newToNative,
          amountBase: newToBase,
          exchangeRate: newToRate,
          clearedAt: toLeg.cleared_at == null ? null : String(toLeg.cleared_at),
          memo: toLeg.memo == null ? null : String(toLeg.memo),
        },
      ],
    };

    if (patch.date !== undefined) entryPatch.date = patch.date;
    if (patch.time !== undefined) entryPatch.time = patch.time ?? null;
    if (patch.note !== undefined) entryPatch.notes = patch.note ?? null;

    await rebuildEntry(exec, entryId, entryPatch);
    return;
  }

  // Header-only patch (date/time/note without amounts).
  const headerPatch: import('@/lib/db/entries').EntryPatch = {};
  if (patch.date !== undefined) headerPatch.date = patch.date;
  if (patch.time !== undefined) headerPatch.time = patch.time ?? null;
  if (patch.note !== undefined) headerPatch.notes = patch.note ?? null;
  if (Object.keys(headerPatch).length > 0) {
    await rebuildEntry(exec, entryId, headerPatch);
  }
}

/**
 * Delete a transfer entry: removes the whole entry (both account legs cascade).
 * Recomputes balances of the affected accounts (recomputeAccountFromPostings).
 */
export async function deleteTransfer(exec: Exec, groupId: string): Promise<void> {
  const ref = await resolveEntryRef(exec, groupId);
  if (!ref) return;
  await deleteEntry(exec, ref.entryId);
}
