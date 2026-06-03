// DB-backed holdings interactions: per-position rows inside an investment-type
// account. Cash lives in accounts.current_balance (driven by transactions); the
// holding rows here carry shares + cost basis + the last price the user logged.
// Prices are kept as a single "last seen" pair (no history table); updates
// overwrite the previous values.

import type { Exec } from '@/lib/db/repo';

export interface Holding {
  id: string;
  ledgerId: string;
  accountId: string;
  symbol: string;
  name: string | null;
  shares: number;
  /** Total amount paid in `currency`. Per-share average = costBasis / shares. */
  costBasis: number;
  currency: string;
  /** Last price the user logged (per share, in `currency`). Null until set. */
  lastPrice: number | null;
  /** YYYY-MM-DD the lastPrice was effective on. Null until set. */
  lastPriceDate: string | null;
  notes: string | null;
}

function rowToHolding(r: Record<string, unknown>): Holding {
  return {
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    accountId: String(r.account_id),
    symbol: String(r.symbol),
    name: r.name == null ? null : String(r.name),
    shares: Number(r.shares),
    costBasis: Number(r.cost_basis),
    currency: String(r.currency),
    lastPrice: r.last_price == null ? null : Number(r.last_price),
    lastPriceDate: r.last_price_date == null ? null : String(r.last_price_date),
    notes: r.notes == null ? null : String(r.notes),
  };
}

/** List holdings. Pass a ledgerId to scope; passing accountId scopes further. */
export async function listHoldings(exec: Exec, ledgerId?: string, accountId?: string): Promise<Holding[]> {
  const where: string[] = [];
  const bind: (string | number | null)[] = [];
  if (ledgerId) {
    where.push('ledger_id = ?');
    bind.push(ledgerId);
  }
  if (accountId) {
    where.push('account_id = ?');
    bind.push(accountId);
  }
  const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const rows = await exec(
    `SELECT * FROM holdings ${clause} ORDER BY symbol, created_at`,
    bind,
  );
  return rows.map(rowToHolding);
}

export async function getHolding(exec: Exec, id: string): Promise<Holding | null> {
  const rows = await exec('SELECT * FROM holdings WHERE id = ?', [id]);
  return rows[0] ? rowToHolding(rows[0]) : null;
}

export interface NewHolding {
  id: string;
  ledgerId: string;
  accountId: string;
  symbol: string;
  name?: string | null;
  shares: number;
  costBasis: number;
  /** Defaults to the account's currency when omitted. */
  currency?: string;
  /** Optional initial price; pair with lastPriceDate when provided. */
  lastPrice?: number | null;
  lastPriceDate?: string | null;
  notes?: string | null;
}

/** Insert a new holding row. The account must be an investment-type account —
 *  the caller (mutation handler) checks this; SQL has no CHECK against type. */
export async function createHolding(exec: Exec, h: NewHolding): Promise<void> {
  const [acct] = await exec('SELECT currency FROM accounts WHERE id = ?', [h.accountId]);
  const currency = h.currency ?? String(acct?.currency ?? 'USD');
  await exec(
    `INSERT INTO holdings
       (id,ledger_id,account_id,symbol,name,shares,cost_basis,currency,last_price,last_price_date,notes,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))`,
    [
      h.id, h.ledgerId, h.accountId, h.symbol.toUpperCase(), h.name ?? null,
      h.shares, h.costBasis, currency, h.lastPrice ?? null, h.lastPriceDate ?? null, h.notes ?? null,
    ],
  );
}

export interface HoldingPatch {
  symbol?: string;
  name?: string | null;
  shares?: number;
  costBasis?: number;
  notes?: string | null;
}

const PATCH_COLUMNS: Record<keyof HoldingPatch, string> = {
  symbol: 'symbol',
  name: 'name',
  shares: 'shares',
  costBasis: 'cost_basis',
  notes: 'notes',
};

/** Update a holding's editable fields. currency, account, and the price pair
 *  are intentionally not patchable here — currency is fixed at creation
 *  (changing it would re-interpret cost basis), and price moves through the
 *  dedicated setHoldingPrice (so both halves of the pair update atomically). */
export async function updateHolding(exec: Exec, id: string, patch: HoldingPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof HoldingPatch)[]) {
    const value = patch[key];
    if (value === undefined) continue;
    const col = PATCH_COLUMNS[key];
    if (!col) continue;
    sets.push(`${col} = ?`);
    bind.push(typeof value === 'string' && key === 'symbol' ? value.toUpperCase() : value);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE holdings SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Set the live price for a holding. Pass both halves so they stay paired;
 *  pass null/null to clear them (e.g. "no longer have a quote"). */
export async function setHoldingPrice(
  exec: Exec,
  id: string,
  price: number | null,
  date: string | null,
): Promise<void> {
  await exec(
    "UPDATE holdings SET last_price = ?, last_price_date = ?, updated_at = datetime('now') WHERE id = ?",
    [price, date, id],
  );
}

export async function deleteHolding(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM holdings WHERE id = ?', [id]);
}
