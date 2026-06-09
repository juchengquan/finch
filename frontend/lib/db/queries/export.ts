// Human-readable exports built from the DB (names resolved via joins), distinct
// from the raw SQLite-file backup. Currently: transactions as CSV.

import type { Exec } from '../core/repo';
import { toCsv, type CsvColumn } from '@/lib/csv';
import type { TxExportFilter, TxExportRow } from '@/lib/db/domain/_app/export.types';

const COLUMNS: CsvColumn[] = [
  { key: 'date', label: 'Date' },
  { key: 'time', label: 'Time' },
  { key: 'ledger', label: 'Ledger' },
  { key: 'account', label: 'Account' },
  { key: 'merchant', label: 'Merchant' },
  { key: 'category', label: 'Category' },
  { key: 'amount', label: 'Amount' },
  { key: 'currency', label: 'Currency' },
  { key: 'amountBase', label: 'Amount (base)' },
  { key: 'status', label: 'Status' },
  { key: 'kind', label: 'Type' },
  { key: 'note', label: 'Note' },
  { key: 'tags', label: 'Tags' },
];

/** Transactions with account/category names + tag list, newest first.
 *  One row per account leg; opening entries excluded. */
export async function transactionExportRows(exec: Exec, filter: TxExportFilter = {}): Promise<TxExportRow[]> {
  const where: string[] = ['p.account_id IS NOT NULL', "e.kind != 'opening'"];
  const bind: (string | number)[] = [];
  if (filter.ledgerId) {
    where.push('e.ledger_id = ?');
    bind.push(filter.ledgerId);
  }
  if (filter.month) {
    where.push('e.date LIKE ?');
    bind.push(`${filter.month}%`);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const rows = await exec(
    `SELECT e.date, e.time, e.ledger_id AS ledger,
            a.name AS account,
            COALESCE(p.memo, e.description) AS merchant,
            (SELECT cc.name
               FROM postings cp
               JOIN categories cc ON cc.id = cp.category_id
              WHERE cp.entry_id = e.id AND cp.account_id IS NULL AND cc.kind != 'equity'
              ORDER BY ABS(cp.amount_base) DESC LIMIT 1) AS category,
            p.amount, p.currency, p.amount_base AS amountBase, e.status, e.kind, e.notes AS note,
            (SELECT GROUP_CONCAT(tg.name, '; ')
               FROM entry_tags et JOIN tags tg ON et.tag_id = tg.id
              WHERE et.entry_id = e.id) AS tags
       FROM postings p
       JOIN entries e ON e.id = p.entry_id
       LEFT JOIN accounts a ON p.account_id = a.id
      ${whereSql}
      ORDER BY e.date DESC, e.time DESC, e.created_at DESC`,
    bind,
  );
  return rows.map((r) => ({
    date: String(r.date ?? ''),
    time: r.time == null ? '' : String(r.time),
    ledger: String(r.ledger ?? ''),
    account: r.account == null ? '' : String(r.account),
    merchant: r.merchant == null ? '' : String(r.merchant),
    category: r.category == null ? '' : String(r.category),
    amount: Number(r.amount ?? 0),
    currency: String(r.currency ?? ''),
    amountBase: Number(r.amountBase ?? 0),
    status: String(r.status ?? ''),
    kind: String(r.kind ?? ''),
    note: r.note == null ? '' : String(r.note),
    tags: r.tags == null ? '' : String(r.tags),
  }));
}

export async function transactionsCsv(exec: Exec, filter: TxExportFilter = {}): Promise<string> {
  const rows = await transactionExportRows(exec, filter);
  return toCsv(rows as unknown as Record<string, unknown>[], COLUMNS);
}
