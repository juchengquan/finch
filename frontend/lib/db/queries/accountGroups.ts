// CRUD for account_groups. Groups bucket accounts on the Accounts screen — pure
// organisational metadata (name + sort order). The per-account net-worth flag
// lives on accounts.include_in_net_worth and is defaulted by `type` at create
// time; there is no group-level default any more.

import type { Exec } from '../core/repo';

export interface AccountGroupRow {
  id: string;
  ledgerId: string;
  name: string;
  sortOrder: number;
}

/** List groups; pass a ledgerId to scope, or omit for all ledgers. */
export async function listAccountGroups(exec: Exec, ledgerId?: string): Promise<AccountGroupRow[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT id, ledger_id AS ledgerId, name, sort_order AS sortOrder FROM account_groups WHERE ledger_id = ? ORDER BY sort_order, name'
      : 'SELECT id, ledger_id AS ledgerId, name, sort_order AS sortOrder FROM account_groups ORDER BY ledger_id, sort_order, name',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledgerId),
    name: String(r.name),
    sortOrder: Number(r.sortOrder),
  }));
}

export interface NewAccountGroup {
  id: string;
  ledgerId: string;
  name: string;
}

/** Insert a group; sort_order is appended after the existing ones in the ledger. */
export async function createAccountGroup(exec: Exec, g: NewAccountGroup): Promise<void> {
  const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM account_groups WHERE ledger_id = ?', [g.ledgerId]);
  const sortOrder = Number(rows[0]?.n ?? 0);
  await exec(
    `INSERT INTO account_groups (id,ledger_id,name,sort_order,created_at,updated_at)
     VALUES (?,?,?,?,datetime('now'),datetime('now'))`,
    [g.id, g.ledgerId, g.name, sortOrder],
  );
}

export interface AccountGroupPatch {
  name?: string;
}

export async function updateAccountGroup(exec: Exec, id: string, patch: AccountGroupPatch): Promise<void> {
  if (patch.name === undefined) return;
  await exec(
    "UPDATE account_groups SET name = ?, updated_at = datetime('now') WHERE id = ?",
    [patch.name, id],
  );
}

/** Hard-delete a group; accounts in it get group_id = NULL via the schema FK. */
export async function deleteAccountGroup(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM account_groups WHERE id = ?', [id]);
}
