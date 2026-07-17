// CRUD for budget_groups. Groups bucket named budgets on the Budgets screen,
// exactly like account_groups bucket accounts. Deleting a group sets its
// budgets' group_id to NULL via the schema FK (ON DELETE SET NULL).

import type { Exec } from '../core/repo';
import type { BudgetGroupRow, NewBudgetGroup, BudgetGroupPatch } from '@/lib/db/domain/budgetGroups/types';

/** List groups; pass a ledgerId to scope, or omit for all ledgers. */
export async function listBudgetGroups(exec: Exec, ledgerId?: string): Promise<BudgetGroupRow[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT id, ledger_id AS ledgerId, name, color, sort_order AS sortOrder FROM budget_groups WHERE ledger_id = ? ORDER BY sort_order, name'
      : 'SELECT id, ledger_id AS ledgerId, name, color, sort_order AS sortOrder FROM budget_groups ORDER BY ledger_id, sort_order, name',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledgerId),
    name: String(r.name),
    color: r.color == null ? null : String(r.color),
    sortOrder: Number(r.sortOrder),
  }));
}

/** Insert a group; sort_order is appended after the existing ones in the ledger. */
export async function createBudgetGroup(exec: Exec, g: NewBudgetGroup): Promise<void> {
  const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM budget_groups WHERE ledger_id = ?', [g.ledgerId]);
  const sortOrder = Number(rows[0]?.n ?? 0);
  await exec(
    `INSERT INTO budget_groups (id,ledger_id,name,color,sort_order,created_at,updated_at)
     VALUES (?,?,?,?,?,datetime('now'),datetime('now'))`,
    [g.id, g.ledgerId, g.name, g.color ?? null, sortOrder],
  );
}

export async function updateBudgetGroup(exec: Exec, id: string, patch: BudgetGroupPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  if (patch.name !== undefined) { sets.push('name = ?'); bind.push(patch.name); }
  if (patch.color !== undefined) { sets.push('color = ?'); bind.push(patch.color); }
  if (patch.sortOrder !== undefined) { sets.push('sort_order = ?'); bind.push(patch.sortOrder); }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE budget_groups SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Hard-delete a group; its budgets get group_id = NULL via the schema FK. */
export async function deleteBudgetGroup(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM budget_groups WHERE id = ?', [id]);
}
