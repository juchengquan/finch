// Scheduled templates + their splits, projected back into the store shape.
// Accounts are referenced by display name (account_name); ids are resolved at
// post time in lib/db/mutations.ts.

import type { Exec } from '@/lib/db/repo';
import type { ScheduledTemplate, ScheduledSplit } from '@/lib/store';

export async function listScheduled(exec: Exec, ledgerId?: string): Promise<ScheduledTemplate[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM scheduled_templates WHERE ledger_id = ? ORDER BY rowid'
      : 'SELECT * FROM scheduled_templates ORDER BY ledger_id, rowid',
    ledgerId ? [ledgerId] : [],
  );
  const splitRows = await exec('SELECT * FROM scheduled_splits ORDER BY template_id, sort_order');
  const splitsByTemplate = new Map<string, ScheduledSplit[]>();
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
      weekDay: r.day_of_week == null ? undefined : Number(r.day_of_week),
      account: String(r.account_name ?? ''),
      from: r.from_account_name == null ? undefined : String(r.from_account_name),
      autoPost: Number(r.auto_post),
      nextRun: String(r.next_run ?? ''),
      lastRun: String(r.last_run ?? ''),
      color: r.color == null ? null : String(r.color),
      category: r.category_id == null ? null : String(r.category_id),
      startDate: r.start_date == null ? undefined : String(r.start_date),
      endDate: r.end_date == null ? null : String(r.end_date),
      maxExecutions: r.max_executions == null ? null : Number(r.max_executions),
      ...(splits ? { splits } : {}),
    };
  });
}

export interface ScheduledPatch {
  name?: string;
  amount?: number | null;
  frequency?: string;
  dayOfMonth?: number;
  weekDay?: number;
  autoPost?: number;
  color?: string | null;
  type?: string;
  category?: string | null;
  endDate?: string | null;
  maxExecutions?: number | null;
}

export async function updateScheduled(exec: Exec, id: string, patch: ScheduledPatch): Promise<void> {
  const cols: Record<string, string> = {
    name: 'name', amount: 'amount', frequency: 'frequency', dayOfMonth: 'day_of_month',
    weekDay: 'day_of_week', autoPost: 'auto_post', color: 'color', type: 'type',
    category: 'category_id', endDate: 'end_date', maxExecutions: 'max_executions',
  };
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch)) {
    if (patch[key as keyof ScheduledPatch] === undefined) continue;
    sets.push(`${cols[key]} = ?`);
    bind.push(patch[key as keyof ScheduledPatch] ?? null);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE scheduled_templates SET ${sets.join(', ')} WHERE id = ?`, bind);
}

export interface NewScheduled {
  id: string;
  ledgerId: string;
  name: string;
  type: string;
  amount: number | null;
  frequency: string;
  dayOfMonth: number;
  weekDay: number | null;
  account: string;
  from: string | null;
  autoPost: number;
  color: string | null;
  category: string | null;
  startDate: string;
  endDate: string | null;
  maxExecutions: number | null;
}

export async function createScheduled(exec: Exec, t: NewScheduled): Promise<void> {
  await exec(
    `INSERT INTO scheduled_templates
       (id,ledger_id,name,type,amount,amount_varies,splits_enabled,account_id,account_name,
        from_account_id,from_account_name,category_id,frequency,day_of_month,day_of_week,start_date,
        end_date,max_executions,next_run,last_run,auto_post,color,is_active,created_at,updated_at)
     VALUES (?,?,?,?,?,0,0,NULL,?,NULL,?,?,?,?,?,?,?,?,NULL,NULL,?,?,1,datetime('now'),datetime('now'))`,
    [t.id, t.ledgerId, t.name, t.type, t.amount, t.account, t.from, t.category, t.frequency, t.dayOfMonth, t.weekDay, t.startDate, t.endDate, t.maxExecutions, t.autoPost, t.color],
  );
}

export async function addScheduledSplit(exec: Exec, templateId: string, account: string, pct: number): Promise<void> {
  const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM scheduled_splits WHERE template_id = ?', [templateId]);
  const sort = Number(rows[0]?.n ?? 0);
  const id = `${templateId}-s${sort}-${Math.random().toString(36).slice(2, 8)}`;
  await exec(
    'INSERT INTO scheduled_splits (id,template_id,account_id,account_name,amount_pct,amount_abs,category_id,description,sort_order) VALUES (?,?,NULL,?,?,NULL,NULL,NULL,?)',
    [id, templateId, account, pct, sort],
  );
  await exec("UPDATE scheduled_templates SET splits_enabled = 1, updated_at = datetime('now') WHERE id = ?", [templateId]);
}

export async function removeScheduledSplit(exec: Exec, templateId: string, index: number): Promise<void> {
  await exec(
    `DELETE FROM scheduled_splits
      WHERE id = (SELECT id FROM scheduled_splits WHERE template_id = ? ORDER BY sort_order LIMIT 1 OFFSET ?)`,
    [templateId, index],
  );
  const rows = await exec('SELECT COUNT(*) AS n FROM scheduled_splits WHERE template_id = ?', [templateId]);
  if (Number(rows[0]?.n ?? 0) === 0) {
    await exec("UPDATE scheduled_templates SET splits_enabled = 0, updated_at = datetime('now') WHERE id = ?", [templateId]);
  }
}

export async function deleteScheduled(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM scheduled_templates WHERE id = ?', [id]);
}
