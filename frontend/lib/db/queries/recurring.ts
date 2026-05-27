// Recurring templates + their splits, projected back into the store shape.
// Accounts are referenced by display name (account_name); ids are resolved at
// post time in lib/db/mutations.ts.

import type { Exec } from '@/lib/db/repo';
import type { RecurringTemplate, RecurringSplit } from '@/lib/store';

export async function listRecurring(exec: Exec, ledgerId?: string): Promise<RecurringTemplate[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM recurring_templates WHERE ledger_id = ? ORDER BY rowid'
      : 'SELECT * FROM recurring_templates ORDER BY ledger_id, rowid',
    ledgerId ? [ledgerId] : [],
  );
  const splitRows = await exec('SELECT * FROM recurring_splits ORDER BY template_id, sort_order');
  const splitsByTemplate = new Map<string, RecurringSplit[]>();
  for (const s of splitRows) {
    const arr = splitsByTemplate.get(String(s.template_id)) ?? [];
    arr.push({
      account: String(s.account_name ?? ''),
      pct: Number(s.amount_pct ?? 0),
      abs: s.amount_abs == null ? null : Number(s.amount_abs),
      label: String(s.description ?? ''),
    });
    splitsByTemplate.set(String(s.template_id), arr);
  }
  return rows.map((r) => {
    const id = String(r.id);
    const splits = splitsByTemplate.get(id);
    return {
      id,
      name: String(r.name ?? ''),
      type: String(r.type),
      amount: r.amount == null ? null : Number(r.amount),
      varies: Number(r.amount_varies),
      frequency: String(r.frequency),
      dayOfMonth: Number(r.day_of_month ?? 1),
      account: String(r.account_name ?? ''),
      from: r.from_account_name == null ? undefined : String(r.from_account_name),
      autoPost: Number(r.auto_post),
      nextRun: String(r.next_run ?? ''),
      lastRun: String(r.last_run ?? ''),
      ...(splits ? { splits } : {}),
    };
  });
}

export interface RecurringPatch {
  name?: string;
  amount?: number | null;
  frequency?: string;
  dayOfMonth?: number;
  autoPost?: number;
}

/** Update a recurring template's editable fields. */
export async function updateRecurring(exec: Exec, id: string, patch: RecurringPatch): Promise<void> {
  const cols: Record<keyof RecurringPatch, string> = {
    name: 'name', amount: 'amount', frequency: 'frequency', dayOfMonth: 'day_of_month', autoPost: 'auto_post',
  };
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof RecurringPatch)[]) {
    if (patch[key] === undefined) continue;
    sets.push(`${cols[key]} = ?`);
    bind.push(patch[key] ?? null);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE recurring_templates SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Hard delete a recurring template; recurring_splits cascade away via the FK. */
export async function deleteRecurring(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM recurring_templates WHERE id = ?', [id]);
}
