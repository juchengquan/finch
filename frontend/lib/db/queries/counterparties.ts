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

/** Hard delete a merchant. `transactions.counterparty_id` is a real FK with
 *  ON DELETE SET NULL, so historical rows survive — but they lose the
 *  catalog rename projection (projectState overrides each linked row's
 *  description with the counterparty's name; once the FK is null the row
 *  falls back to whatever `description` text was last written). */
export async function deleteCounterparty(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM counterparties WHERE id = ?', [id]);
}

/** Resolve a free-text merchant string to a counterparty id by case-insensitive
 *  exact match within the same ledger. Returns null when no row matches —
 *  callers leave `transactions.counterparty_id` NULL and the description
 *  stands on its own. Auto-creating counterparties from typed names is
 *  intentionally NOT done here: the catalog stays curated. */
export async function resolveCounterpartyIdByName(
  exec: Exec,
  ledgerId: string,
  name: string | null | undefined,
): Promise<string | null> {
  if (!name) return null;
  const trimmed = name.trim();
  if (!trimmed) return null;
  // The name column is COLLATE NOCASE, so `=` matches case-insensitively and
  // the (ledger_id, name) index serves the lookup directly — no LOWER() needed.
  const rows = await exec(
    'SELECT id FROM counterparties WHERE ledger_id = ? AND name = ? LIMIT 1',
    [ledgerId, trimmed],
  );
  return rows.length ? String(rows[0].id) : null;
}
