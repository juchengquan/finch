// DB-backed merchant/counterparty interactions: list, search, verify, alias.

import type { Exec } from '@/lib/db/repo';

export interface Counterparty {
  id: string;
  ledgerId: string;
  name: string;
  aliases: string[];
  category: string | null;
  verified: boolean;
}

function rowToCp(r: Record<string, unknown>): Counterparty {
  return {
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    name: String(r.standardized_name),
    aliases: r.aliases ? (JSON.parse(String(r.aliases)) as string[]) : [],
    category: r.category == null ? null : String(r.category),
    verified: !!Number(r.is_verified),
  };
}

/** List counterparties; pass a ledgerId to scope, or omit for all ledgers. */
export async function listCounterparties(exec: Exec, ledgerId?: string): Promise<Counterparty[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM counterparties WHERE ledger_id = ? ORDER BY standardized_name'
      : 'SELECT * FROM counterparties ORDER BY ledger_id, standardized_name',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map(rowToCp);
}

/** Match the canonical name or any alias (case-insensitive substring). */
export async function searchCounterparties(exec: Exec, ledgerId: string, query: string): Promise<Counterparty[]> {
  const rows = await exec(
    `SELECT * FROM counterparties
      WHERE ledger_id = ? AND (standardized_name LIKE ? OR aliases LIKE ?)
      ORDER BY standardized_name`,
    [ledgerId, `%${query}%`, `%${query}%`],
  );
  return rows.map(rowToCp);
}

export async function verifyCounterparty(exec: Exec, id: string): Promise<void> {
  await exec('UPDATE counterparties SET is_verified = 1 WHERE id = ?', [id]);
}

export async function addAlias(exec: Exec, id: string, alias: string): Promise<void> {
  const rows = await exec('SELECT aliases FROM counterparties WHERE id = ?', [id]);
  if (!rows[0]) return;
  const aliases = rows[0].aliases ? (JSON.parse(String(rows[0].aliases)) as string[]) : [];
  if (!aliases.includes(alias)) aliases.push(alias);
  await exec('UPDATE counterparties SET aliases = ? WHERE id = ?', [JSON.stringify(aliases), id]);
}

/** Hard delete a merchant; transactions.counterparty_id becomes NULL via the FK. */
export async function deleteCounterparty(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM counterparties WHERE id = ?', [id]);
}
