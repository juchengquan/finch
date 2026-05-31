// DB-backed merchant/counterparty interactions: list, search, verify.
// The table is a catalog of canonical merchant names — there is no FK from
// transactions; the link is informational only.

import type { Exec } from '@/lib/db/repo';

export interface Counterparty {
  id: string;
  ledgerId: string;
  name: string;
  verified: boolean;
}

function rowToCp(r: Record<string, unknown>): Counterparty {
  return {
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    name: String(r.name),
    verified: !!Number(r.is_verified),
  };
}

/** List counterparties; pass a ledgerId to scope, or omit for all ledgers. */
export async function listCounterparties(exec: Exec, ledgerId?: string): Promise<Counterparty[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM counterparties WHERE ledger_id = ? ORDER BY name'
      : 'SELECT * FROM counterparties ORDER BY ledger_id, name',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map(rowToCp);
}

/** Match the canonical name (case-insensitive substring). */
export async function searchCounterparties(exec: Exec, ledgerId: string, query: string): Promise<Counterparty[]> {
  const rows = await exec(
    `SELECT * FROM counterparties
      WHERE ledger_id = ? AND name LIKE ?
      ORDER BY name`,
    [ledgerId, `%${query}%`],
  );
  return rows.map(rowToCp);
}

export async function verifyCounterparty(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE counterparties SET is_verified = 1, updated_at = datetime('now') WHERE id = ?", [id]);
}

export async function unverifyCounterparty(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE counterparties SET is_verified = 0, updated_at = datetime('now') WHERE id = ?", [id]);
}

export interface NewCounterparty {
  id: string;
  ledgerId: string;
  name: string;
}

/** Insert a new (unverified) merchant. */
export async function createCounterparty(exec: Exec, c: NewCounterparty): Promise<void> {
  await exec(
    "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES (?,?,?,0,datetime('now'),datetime('now'))",
    [c.id, c.ledgerId, c.name],
  );
}

export interface CounterpartyPatch {
  name?: string;
}

/** Update a merchant's editable fields (canonical name only — category lives
 *  on transactions, not merchants). */
export async function updateCounterparty(exec: Exec, id: string, patch: CounterpartyPatch): Promise<void> {
  if (patch.name === undefined) return;
  await exec(
    "UPDATE counterparties SET name = ?, updated_at = datetime('now') WHERE id = ?",
    [patch.name, id],
  );
}

/** Hard delete a merchant. (No FK link from transactions — counterparty data
 *  lives entirely in this table; transaction display uses the description
 *  field.) */
export async function deleteCounterparty(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM counterparties WHERE id = ?', [id]);
}
