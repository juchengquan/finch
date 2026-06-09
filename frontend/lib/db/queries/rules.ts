// DB-backed conditional rules (RULES_ENGINE_PLAN). The condition tree and
// action list live as JSON text columns; this layer is the (de)serialization
// boundary — everything above it works with the typed Rule shape.

import type { Exec } from '../core/repo';
import type { Rule, NewRule, Condition, Action } from '@/lib/rules/types';

function parseCondition(raw: unknown): Condition {
  try {
    return JSON.parse(String(raw)) as Condition;
  } catch {
    // A corrupt condition matches nothing rather than throwing on read.
    return { all: [{ field: 'amount', op: 'lt', value: -1e18 }] };
  }
}

function parseActions(raw: unknown): Action[] {
  try {
    const v = JSON.parse(String(raw));
    return Array.isArray(v) ? (v as Action[]) : [];
  } catch {
    return [];
  }
}

export function rowToRule(r: Record<string, unknown>): Rule {
  return {
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    name: r.name == null ? null : String(r.name),
    priority: Number(r.priority ?? 100),
    condition: parseCondition(r.condition),
    actions: parseActions(r.actions),
    isActive: !!Number(r.is_active),
    runOnEdit: !!Number(r.run_on_edit),
    lastAppliedAt: r.last_applied_at == null ? null : String(r.last_applied_at),
  };
}

/** List rules; pass a ledgerId to scope, or omit for all ledgers. Ordered by
 *  priority (the apply order), then created_at for a stable tie-break. */
export async function listRules(exec: Exec, ledgerId?: string): Promise<Rule[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM rules WHERE ledger_id = ? ORDER BY priority, created_at'
      : 'SELECT * FROM rules ORDER BY ledger_id, priority, created_at',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map(rowToRule);
}

/** Active rules for a ledger, in apply order. The engine's input. */
export async function listActiveRules(exec: Exec, ledgerId: string): Promise<Rule[]> {
  const rows = await exec(
    'SELECT * FROM rules WHERE ledger_id = ? AND is_active = 1 ORDER BY priority, created_at',
    [ledgerId],
  );
  return rows.map(rowToRule);
}

export async function createRule(exec: Exec, id: string, r: NewRule): Promise<void> {
  await exec(
    `INSERT INTO rules
       (id, ledger_id, name, priority, condition, actions, is_active, run_on_edit,
        created_at, updated_at)
     VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))`,
    [
      id,
      r.ledgerId,
      r.name ?? null,
      r.priority ?? 100,
      JSON.stringify(r.condition),
      JSON.stringify(r.actions),
      r.isActive === false ? 0 : 1,
      r.runOnEdit ? 1 : 0,
    ],
  );
}

export interface RulePatchInput {
  name?: string | null;
  priority?: number;
  condition?: Condition;
  actions?: Action[];
  isActive?: boolean;
  runOnEdit?: boolean;
}

export async function updateRule(exec: Exec, id: string, patch: RulePatchInput): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  if (patch.name !== undefined) { sets.push('name = ?'); bind.push(patch.name); }
  if (patch.priority !== undefined) { sets.push('priority = ?'); bind.push(patch.priority); }
  if (patch.condition !== undefined) { sets.push('condition = ?'); bind.push(JSON.stringify(patch.condition)); }
  if (patch.actions !== undefined) { sets.push('actions = ?'); bind.push(JSON.stringify(patch.actions)); }
  if (patch.isActive !== undefined) { sets.push('is_active = ?'); bind.push(patch.isActive ? 1 : 0); }
  if (patch.runOnEdit !== undefined) { sets.push('run_on_edit = ?'); bind.push(patch.runOnEdit ? 1 : 0); }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE rules SET ${sets.join(', ')} WHERE id = ?`, bind);
}

export async function deleteRule(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM rules WHERE id = ?', [id]);
}

/** Stamp last_applied_at after a backfill run. */
export async function markRuleApplied(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE rules SET last_applied_at = datetime('now') WHERE id = ?", [id]);
}
