// DB-backed merchant/counterparty interactions: list, search, verify.
// The table is a catalog of canonical merchant names — there is no FK from
// transactions; the link is informational only.

import type { Exec } from '../core/repo';
import type { Counterparty, NewCounterparty, CounterpartyPatch } from '@/lib/db/domain/counterparties/types';

function rowToCp(r: Record<string, unknown>): Counterparty {
  return {
    id: String(r.id),
    name: String(r.name),
    verified: !!Number(r.is_verified),
  };
}

/** List all counterparties. Merchants are global — one shared catalog. */
export async function listCounterparties(exec: Exec): Promise<Counterparty[]> {
  const rows = await exec('SELECT * FROM counterparties ORDER BY name');
  return rows.map(rowToCp);
}

/** Match the canonical name (case-insensitive substring), globally. */
export async function searchCounterparties(exec: Exec, query: string): Promise<Counterparty[]> {
  const rows = await exec(
    `SELECT * FROM counterparties
      WHERE name LIKE ?
      ORDER BY name`,
    [`%${query}%`],
  );
  return rows.map(rowToCp);
}

export async function verifyCounterparty(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE counterparties SET is_verified = 1, updated_at = datetime('now') WHERE id = ?", [id]);
}

export async function unverifyCounterparty(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE counterparties SET is_verified = 0, updated_at = datetime('now') WHERE id = ?", [id]);
}

/** Insert a new (unverified) merchant. */
export async function createCounterparty(exec: Exec, c: NewCounterparty): Promise<void> {
  await exec(
    "INSERT INTO counterparties (id,name,is_verified,created_at,updated_at) VALUES (?,?,0,datetime('now'),datetime('now'))",
    [c.id, c.name],
  );
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
 *  exact match against the global catalog. Returns null when no row matches —
 *  callers leave `transactions.counterparty_id` NULL and the description
 *  stands on its own. Auto-creating counterparties from typed names is
 *  intentionally NOT done here: the catalog stays curated. */
export async function resolveCounterpartyIdByName(
  exec: Exec,
  name: string | null | undefined,
): Promise<string | null> {
  if (!name) return null;
  const trimmed = name.trim();
  if (!trimmed) return null;
  // The name column is COLLATE NOCASE, so `=` matches case-insensitively and
  // the name index serves the lookup directly — no LOWER() needed.
  const rows = await exec(
    'SELECT id FROM counterparties WHERE name = ? LIMIT 1',
    [trimmed],
  );
  return rows.length ? String(rows[0].id) : null;
}
