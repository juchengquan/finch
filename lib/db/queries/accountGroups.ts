// CRUD for account_groups. Groups bucket accounts on the Accounts screen and
// control the default `include_in_net_worth` for their members (an account can
// still override individually via accounts.include_in_net_worth).

import type { Exec } from '@/lib/db/repo';

export interface AccountGroupRow {
  id: string;
  ledgerId: string;
  name: string;
  includeInNetWorth: number;
  sortOrder: number;
}

/** List groups; pass a ledgerId to scope, or omit for all ledgers. */
export async function listAccountGroups(exec: Exec, ledgerId?: string): Promise<AccountGroupRow[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT id, ledger_id AS ledgerId, name, include_in_net_worth AS inw, sort_order AS sortOrder FROM account_groups WHERE ledger_id = ? ORDER BY sort_order, name'
      : 'SELECT id, ledger_id AS ledgerId, name, include_in_net_worth AS inw, sort_order AS sortOrder FROM account_groups ORDER BY ledger_id, sort_order, name',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledgerId),
    name: String(r.name),
    includeInNetWorth: Number(r.inw),
    sortOrder: Number(r.sortOrder),
  }));
}

export interface NewAccountGroup {
  id: string;
  ledgerId: string;
  name: string;
  includeInNetWorth?: number;
}

/** Insert a group; sort_order is appended after the existing ones in the ledger. */
export async function createAccountGroup(exec: Exec, g: NewAccountGroup): Promise<void> {
  const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM account_groups WHERE ledger_id = ?', [g.ledgerId]);
  const sortOrder = Number(rows[0]?.n ?? 0);
  await exec(
    `INSERT INTO account_groups (id,ledger_id,name,include_in_net_worth,sort_order,created_at,updated_at)
     VALUES (?,?,?,?,?,datetime('now'),datetime('now'))`,
    [g.id, g.ledgerId, g.name, g.includeInNetWorth ?? 1, sortOrder],
  );
}

export interface AccountGroupPatch {
  name?: string;
  includeInNetWorth?: number;
}

const PATCH_COLUMNS: Record<keyof AccountGroupPatch, string> = {
  name: 'name',
  includeInNetWorth: 'include_in_net_worth',
};

export async function updateAccountGroup(exec: Exec, id: string, patch: AccountGroupPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof AccountGroupPatch)[]) {
    const value = patch[key];
    if (value === undefined) continue;
    sets.push(`${PATCH_COLUMNS[key]} = ?`);
    bind.push(value ?? null);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE account_groups SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Hard-delete a group; accounts in it get group_id = NULL via the schema FK. */
export async function deleteAccountGroup(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM account_groups WHERE id = ?', [id]);
}
