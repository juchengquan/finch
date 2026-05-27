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

export interface NewRecurring {
  id: string;
  ledgerId: string;
  name: string;
  type: string;
  amount: number | null;
  frequency: string;
  dayOfMonth: number;
  account: string;
  from: string | null;
  autoPost: number;
}

/** Insert a new recurring template (accounts are referenced by name, like the seed). */
export async function createRecurring(exec: Exec, t: NewRecurring): Promise<void> {
  await exec(
    `INSERT INTO recurring_templates
       (id,ledger_id,name,type,amount,amount_varies,splits_enabled,account_id,account_name,
        from_account_id,from_account_name,category_id,frequency,day_of_month,start_date,
        next_run,last_run,auto_post,is_active,created_at,updated_at)
     VALUES (?,?,?,?,?,0,0,NULL,?,NULL,?,NULL,?,?,date('now'),NULL,NULL,?,1,datetime('now'),datetime('now'))`,
    [t.id, t.ledgerId, t.name, t.type, t.amount, t.account, t.from, t.frequency, t.dayOfMonth, t.autoPost],
  );
}

/** Append a split (referenced by account name) and mark the template split-enabled. */
export async function addRecurringSplit(exec: Exec, templateId: string, account: string, pct: number): Promise<void> {
  const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM recurring_splits WHERE template_id = ?', [templateId]);
  const sort = Number(rows[0]?.n ?? 0);
  const id = `${templateId}-s${sort}-${Math.random().toString(36).slice(2, 8)}`;
  await exec(
    'INSERT INTO recurring_splits (id,template_id,account_id,account_name,amount_pct,amount_abs,category_id,description,sort_order) VALUES (?,?,NULL,?,?,NULL,NULL,NULL,?)',
    [id, templateId, account, pct, sort],
  );
  await exec("UPDATE recurring_templates SET splits_enabled = 1, updated_at = datetime('now') WHERE id = ?", [templateId]);
}

/** Remove the nth split (by sort order); clears split-enabled when none remain. */
export async function removeRecurringSplit(exec: Exec, templateId: string, index: number): Promise<void> {
  await exec(
    `DELETE FROM recurring_splits
      WHERE id = (SELECT id FROM recurring_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)`,
    [templateId, index],
  );
  const rows = await exec('SELECT COUNT(*) AS n FROM recurring_splits WHERE template_id = ?', [templateId]);
  if (Number(rows[0]?.n ?? 0) === 0) {
    await exec("UPDATE recurring_templates SET splits_enabled = 0, updated_at = datetime('now') WHERE id = ?", [templateId]);
  }
}

/** Hard delete a recurring template; recurring_splits cascade away via the FK. */
export async function deleteRecurring(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM recurring_templates WHERE id = ?', [id]);
}
