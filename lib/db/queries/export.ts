// Human-readable exports built from the DB (names resolved via joins), distinct
// from the raw SQLite-file backup. Currently: transactions as CSV.

import type { Exec } from '@/lib/db/repo';
import { toCsv, type CsvColumn } from '@/lib/csv';

export interface TxExportRow {
  date: string;
  time: string;
  ledger: string;
  account: string;
  merchant: string;
  category: string;
  amount: number;
  currency: string;
  amountBase: number;
  status: string;
  kind: string;
  note: string;
  tags: string;
}

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

/** Optional scoping for a transactions export. Both filters are independent;
 *  omit for the full all-ledgers export (the Settings backup behaviour). */
export interface TxExportFilter {
  /** Restrict to one ledger. */
  ledgerId?: string;
  /** Restrict to a single YYYY-MM month (matched against the txn date). */
  month?: string;
}

/** Transactions with account/category names + tag list, newest first. */
export async function transactionExportRows(exec: Exec, filter: TxExportFilter = {}): Promise<TxExportRow[]> {
  const where: string[] = [];
  const bind: (string | number)[] = [];
  if (filter.ledgerId) {
    where.push('t.ledger_id = ?');
    bind.push(filter.ledgerId);
  }
  if (filter.month) {
    where.push('t.date LIKE ?');
    bind.push(`${filter.month}%`);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const rows = await exec(
    `SELECT t.date, t.time, t.ledger_id AS ledger,
            a.name AS account, t.description AS merchant, c.name AS category,
            t.amount, t.currency, t.amount_base AS amountBase, t.status, t.kind, t.notes AS note,
            (SELECT GROUP_CONCAT(tg.name, '; ')
               FROM transaction_tags tt JOIN tags tg ON tt.tag_id = tg.id
              WHERE tt.transaction_id = t.id) AS tags
       FROM transactions t
       LEFT JOIN accounts a ON t.account_id = a.id
       LEFT JOIN categories c ON t.category_id = c.id
      ${whereSql}
      ORDER BY t.date DESC, t.time DESC, t.created_at DESC`,
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
