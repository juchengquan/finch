// Scheduled templates + their splits, projected back into the store shape.
// Accounts are real FKs (account_id / from_account_id); display names are
// derived by joining the accounts table at read time, like transactions.

import type { Exec } from '@/lib/db/repo';
import type { ScheduledTemplate, ScheduledSplit } from '@/lib/store';

// installment_paid is derived: count the CONFIRMED entries linked back
// via source_template_id. Pending rows wait for the user's confirm action and
// shouldn't inflate "X of Y paid". Cancelled pending rows are deleted outright,
// so the count naturally stays in sync without any bookkeeping. The aggregate
// is a single GROUP BY scan; correlated subqueries here were quadratic-feel at
// high template counts.
const INSTALLMENT_PAID_JOIN = `LEFT JOIN (
  SELECT source_template_id, COUNT(*) AS n
    FROM entries
   WHERE source_template_id IS NOT NULL AND status = 'confirmed'
   GROUP BY source_template_id
) p ON p.source_template_id = t.id`;

export async function listScheduled(exec: Exec, ledgerId?: string): Promise<ScheduledTemplate[]> {
  const rows = await exec(
    ledgerId
      ? `SELECT t.*, a.name AS account_name, fa.name AS from_account_name,
                COALESCE(p.n, 0) AS installment_paid
           FROM scheduled_templates t
           LEFT JOIN accounts a ON a.id = t.account_id
           LEFT JOIN accounts fa ON fa.id = t.from_account_id
           ${INSTALLMENT_PAID_JOIN}
          WHERE t.ledger_id = ? ORDER BY t.rowid`
      : `SELECT t.*, a.name AS account_name, fa.name AS from_account_name,
                COALESCE(p.n, 0) AS installment_paid
           FROM scheduled_templates t
           LEFT JOIN accounts a ON a.id = t.account_id
           LEFT JOIN accounts fa ON fa.id = t.from_account_id
           ${INSTALLMENT_PAID_JOIN}
          ORDER BY t.ledger_id, t.rowid`,
    ledgerId ? [ledgerId] : [],
  );
  const splitRows = await exec(
    `SELECT s.*, a.name AS account_name
       FROM scheduled_splits s
       LEFT JOIN accounts a ON a.id = s.account_id
      ORDER BY s.template_id, s.sort_order`,
  );
  const splitsByTemplate = new Map<string, ScheduledSplit[]>();
  for (const s of splitRows) {
    const arr = splitsByTemplate.get(String(s.template_id)) ?? [];
    arr.push({
      accountId: String(s.account_id),
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
      description: r.description == null ? null : String(r.description),
      type: String(r.kind),
      amount: r.amount == null ? null : Number(r.amount),
      varies: Number(r.amount_varies),
      frequency: String(r.frequency),
      dayOfMonth: Number(r.day_of_month ?? 1),
      weekDay: r.day_of_week == null ? undefined : Number(r.day_of_week),
      accountId: String(r.account_id),
      account: String(r.account_name ?? ''),
      fromAccountId: r.from_account_id == null ? undefined : String(r.from_account_id),
      from: r.from_account_id == null ? undefined : String(r.from_account_name ?? ''),
      autoPost: Number(r.auto_post),
      nextRun: String(r.next_run ?? ''),
      lastRun: String(r.last_run ?? ''),
      color: r.color == null ? null : String(r.color),
      category: r.category_id == null ? null : String(r.category_id),
      startDate: r.start_date == null ? undefined : String(r.start_date),
      endDate: r.end_date == null ? null : String(r.end_date),
      maxExecutions: r.max_executions == null ? null : Number(r.max_executions),
      installmentTotal: r.installment_total == null ? null : Number(r.installment_total),
      installmentPaid: Number(r.installment_paid ?? 0),
      ...(splits ? { splits } : {}),
    };
  });
}

/** Fetch a single template by id (with its splits + derived installmentPaid).
 *  Cheaper than `listScheduled` for handlers that only need one — the post
 *  path used to re-run the full list query per click. Returns null when the
 *  id doesn't resolve. */
export async function getScheduled(exec: Exec, id: string): Promise<ScheduledTemplate | null> {
  const rows = await exec(
    `SELECT t.*, a.name AS account_name, fa.name AS from_account_name,
            COALESCE(p.n, 0) AS installment_paid
       FROM scheduled_templates t
       LEFT JOIN accounts a ON a.id = t.account_id
       LEFT JOIN accounts fa ON fa.id = t.from_account_id
       ${INSTALLMENT_PAID_JOIN}
      WHERE t.id = ? LIMIT 1`,
    [id],
  );
  if (!rows.length) return null;
  const r = rows[0];
  const splitRows = await exec(
    `SELECT s.*, a.name AS account_name
       FROM scheduled_splits s
       LEFT JOIN accounts a ON a.id = s.account_id
      WHERE s.template_id = ? ORDER BY s.sort_order`,
    [id],
  );
  const splits: ScheduledSplit[] = splitRows.map((s) => ({
    accountId: String(s.account_id),
    account: String(s.account_name ?? ''),
    pct: Number(s.amount_pct ?? 0),
    abs: s.amount_abs == null ? null : Number(s.amount_abs),
    label: String(s.description ?? ''),
  }));
  return {
    id: String(r.id),
    name: String(r.name ?? ''),
    description: r.description == null ? null : String(r.description),
    type: String(r.kind),
    amount: r.amount == null ? null : Number(r.amount),
    varies: Number(r.amount_varies),
    frequency: String(r.frequency),
    dayOfMonth: Number(r.day_of_month ?? 1),
    weekDay: r.day_of_week == null ? undefined : Number(r.day_of_week),
    accountId: String(r.account_id),
    account: String(r.account_name ?? ''),
    fromAccountId: r.from_account_id == null ? undefined : String(r.from_account_id),
    from: r.from_account_id == null ? undefined : String(r.from_account_name ?? ''),
    autoPost: Number(r.auto_post),
    nextRun: String(r.next_run ?? ''),
    lastRun: String(r.last_run ?? ''),
    color: r.color == null ? null : String(r.color),
    category: r.category_id == null ? null : String(r.category_id),
    startDate: r.start_date == null ? undefined : String(r.start_date),
    endDate: r.end_date == null ? null : String(r.end_date),
    maxExecutions: r.max_executions == null ? null : Number(r.max_executions),
    installmentTotal: r.installment_total == null ? null : Number(r.installment_total),
    installmentPaid: Number(r.installment_paid ?? 0),
    ...(splits.length ? { splits } : {}),
  };
}

export interface ScheduledPatch {
  name?: string;
  description?: string | null;
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
  installmentTotal?: number | null;
}

export async function updateScheduled(exec: Exec, id: string, patch: ScheduledPatch): Promise<void> {
  const cols: Record<string, string> = {
    name: 'name', description: 'description', amount: 'amount', frequency: 'frequency', dayOfMonth: 'day_of_month',
    weekDay: 'day_of_week', autoPost: 'auto_post', color: 'color', type: 'kind',
    category: 'category_id', endDate: 'end_date', maxExecutions: 'max_executions',
    installmentTotal: 'installment_total',
  };
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch)) {
    const col = cols[key];
    // Skip undefined values *and* unknown keys — without the latter, a stray
    // patch key (typo, stale field name) becomes `undefined = ?` in SQL and
    // throws an unhelpful "near '=': syntax error" instead of being ignored.
    if (!col || patch[key as keyof ScheduledPatch] === undefined) continue;
    sets.push(`${col} = ?`);
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
  description: string | null;
  type: string;
  amount: number | null;
  frequency: string;
  dayOfMonth: number;
  weekDay: number | null;
  accountId: string;
  fromAccountId: string | null;
  autoPost: number;
  color: string | null;
  category: string | null;
  startDate: string;
  endDate: string | null;
  maxExecutions: number | null;
  installmentTotal: number | null;
}

export async function createScheduled(exec: Exec, t: NewScheduled): Promise<void> {
  await exec(
    `INSERT INTO scheduled_templates
       (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,
        from_account_id,category_id,frequency,day_of_month,day_of_week,start_date,
        end_date,max_executions,installment_total,next_run,last_run,auto_post,color,is_active,created_at,updated_at)
     VALUES (?,?,?,?,?,?,0,0,?,?,?,?,?,?,?,?,?,?,NULL,NULL,?,?,1,datetime('now'),datetime('now'))`,
    [t.id, t.ledgerId, t.name, t.description, t.type, t.amount, t.accountId, t.fromAccountId, t.category, t.frequency, t.dayOfMonth, t.weekDay, t.startDate, t.endDate, t.maxExecutions, t.installmentTotal, t.autoPost, t.color],
  );
}

export async function addScheduledSplit(exec: Exec, templateId: string, accountId: string, pct: number): Promise<void> {
  const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM scheduled_splits WHERE template_id = ?', [templateId]);
  const sort = Number(rows[0]?.n ?? 0);
  const id = `${templateId}-s${sort}-${Math.random().toString(36).slice(2, 8)}`;
  await exec(
    'INSERT INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,category_id,description,sort_order) VALUES (?,?,?,?,NULL,NULL,NULL,?)',
    [id, templateId, accountId, pct, sort],
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
