import type { Tx, PendingItem, RecurringTemplate, AccountOverride } from '@/lib/store';

// A minimal async query interface so the same repo logic works against both the
// in-memory sqlite (tests, via oo1.DB) and the browser OPFS worker (promiser).
export type SqlBind = (string | number | null)[];
export type Row = Record<string, unknown>;
export type Exec = (sql: string, bind?: SqlBind) => Promise<Row[]>;

// The slice of app state we persist (mirrors the Zustand store's partialize).
export interface PersistState {
  transactions: Tx[];
  pending: PendingItem[];
  budgetOverrides: Record<string, number>;
  accountOverrides: Record<string, AccountOverride>;
  verifiedExtra: string[];
  aliasExtra: Record<string, string[]>;
  recurring: RecurringTemplate[];
}

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS transactions (
  id TEXT PRIMARY KEY, merchant TEXT, category TEXT, amount REAL, account TEXT,
  date TEXT, time TEXT, note TEXT, pending INTEGER, recurring INTEGER, kind TEXT, ledger_id TEXT
);
CREATE TABLE IF NOT EXISTS pending (
  id TEXT PRIMARY KEY, merchant TEXT, amount REAL, currency TEXT, date TEXT,
  account TEXT, reason TEXT, source TEXT
);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
`;

export async function initSchema(exec: Exec): Promise<void> {
  await exec(SCHEMA);
}

export async function isEmpty(exec: Exec): Promise<boolean> {
  const rows = await exec('SELECT count(*) AS n FROM transactions');
  return Number(rows[0]?.n ?? 0) === 0;
}

export async function saveState(exec: Exec, s: PersistState): Promise<void> {
  await exec('BEGIN');
  try {
    await exec('DELETE FROM transactions');
    for (const t of s.transactions) {
      await exec(
        'INSERT INTO transactions (id,merchant,category,amount,account,date,time,note,pending,recurring,kind,ledger_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          t.id, t.merchant, t.category, t.amount, t.account, t.date,
          t.time ?? null, t.note ?? null, t.pending ? 1 : 0, t.recurring ? 1 : 0,
          t.kind ?? null, t.ledgerId ?? null,
        ],
      );
    }
    await exec('DELETE FROM pending');
    for (const p of s.pending) {
      await exec('INSERT INTO pending (id,merchant,amount,currency,date,account,reason,source) VALUES (?,?,?,?,?,?,?,?)', [
        p.id, p.merchant, p.amount, p.currency, p.date, p.account, p.reason, p.source,
      ]);
    }
    await exec('DELETE FROM meta');
    const meta: [string, unknown][] = [
      ['budgetOverrides', s.budgetOverrides],
      ['accountOverrides', s.accountOverrides],
      ['verifiedExtra', s.verifiedExtra],
      ['aliasExtra', s.aliasExtra],
      ['recurring', s.recurring],
    ];
    for (const [k, v] of meta) {
      await exec('INSERT INTO meta (key,value) VALUES (?,?)', [k, JSON.stringify(v)]);
    }
    await exec('COMMIT');
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}

export async function loadState(exec: Exec): Promise<PersistState> {
  const txRows = await exec('SELECT * FROM transactions');
  const pendRows = await exec('SELECT * FROM pending');
  const metaRows = await exec('SELECT key, value FROM meta');

  const meta = new Map(metaRows.map((r) => [String(r.key), JSON.parse(String(r.value))]));
  const opt = (v: unknown) => (v === null || v === undefined ? undefined : (v as string));

  return {
    transactions: txRows.map((r) => ({
      id: String(r.id),
      merchant: String(r.merchant),
      category: r.category === null ? null : String(r.category),
      amount: Number(r.amount),
      account: String(r.account),
      date: String(r.date),
      time: opt(r.time),
      note: opt(r.note),
      pending: !!r.pending,
      recurring: !!r.recurring,
      kind: opt(r.kind),
      ledgerId: opt(r.ledger_id),
    })),
    pending: pendRows.map((r) => ({
      id: String(r.id),
      merchant: String(r.merchant),
      amount: Number(r.amount),
      currency: String(r.currency),
      date: String(r.date),
      account: String(r.account),
      reason: String(r.reason),
      source: String(r.source),
    })),
    budgetOverrides: (meta.get('budgetOverrides') as Record<string, number>) ?? {},
    accountOverrides: (meta.get('accountOverrides') as Record<string, AccountOverride>) ?? {},
    verifiedExtra: (meta.get('verifiedExtra') as string[]) ?? [],
    aliasExtra: (meta.get('aliasExtra') as Record<string, string[]>) ?? {},
    recurring: (meta.get('recurring') as RecurringTemplate[]) ?? [],
  };
}
