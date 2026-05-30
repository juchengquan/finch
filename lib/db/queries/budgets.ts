// Named budgets — the only budget model. A budget tracks a set of accounts +
// categories over a cycle, files into a budget group, and is either an expense
// limit or an income target (Goals are income budgets). Legacy per-category
// budgets and the goals table were removed in the budgets redesign.

import type { Exec } from '@/lib/db/repo';

export type BudgetType = 'expense' | 'income';

export interface BudgetRow {
  id: string;
  ledgerId: string;
  groupId: string | null;
  name: string;
  type: BudgetType;
  amount: number;
  /** Manual progress accumulator for one-shot income/goal budgets. */
  saved: number;
  carryForward: number;
  frequency: string;
  startDate: string;
  endDate: string | null;
  isRecurring: number;
  rollover: number;
  rolloverLimit: number | null;
  accountIds: string[];
  categoryIds: string[];
  tagIds: string[];
  warningPct: number;
}

const parseIds = (v: unknown): string[] => {
  if (v == null) return [];
  try {
    const arr = JSON.parse(String(v));
    return Array.isArray(arr) ? arr.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    return [];
  }
};

function rowToBudget(r: Record<string, unknown>): BudgetRow {
  return {
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    groupId: r.group_id == null ? null : String(r.group_id),
    name: r.name == null ? '' : String(r.name),
    type: String(r.type) === 'income' ? 'income' : 'expense',
    amount: Number(r.amount),
    saved: Number(r.saved ?? 0),
    carryForward: Number(r.carry_forward ?? 0),
    frequency: String(r.frequency),
    startDate: String(r.start_date),
    endDate: r.end_date == null ? null : String(r.end_date),
    isRecurring: Number(r.is_recurring ?? 1),
    rollover: Number(r.rollover ?? 0),
    rolloverLimit: r.rollover_limit == null ? null : Number(r.rollover_limit),
    accountIds: parseIds(r.account_ids),
    categoryIds: parseIds(r.category_ids),
    tagIds: parseIds(r.tag_ids),
    warningPct: Number(r.warning_pct ?? 80),
  };
}

/** List all named budgets, optionally scoped to a ledger. */
export async function listBudgets(exec: Exec, ledgerId?: string): Promise<BudgetRow[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM budgets WHERE ledger_id = ? ORDER BY created_at'
      : 'SELECT * FROM budgets ORDER BY ledger_id, created_at',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map(rowToBudget);
}

export interface NewBudget {
  id: string;
  ledgerId: string;
  groupId?: string | null;
  name: string;
  type: BudgetType;
  amount: number;
  saved?: number;
  frequency: string;
  startDate: string;
  endDate?: string | null;
  isRecurring?: number;
  rollover?: number;
  rolloverLimit?: number | null;
  accountIds?: string[];
  categoryIds?: string[];
  tagIds?: string[];
  warningPct?: number;
}

const idsToJson = (ids?: string[]): string | null => (ids && ids.length ? JSON.stringify(ids) : null);

/** Insert a named budget. */
export async function createBudget(exec: Exec, b: NewBudget): Promise<void> {
  await exec(
    `INSERT INTO budgets
       (id, ledger_id, group_id, name, type, amount, saved, carry_forward,
        frequency, start_date, end_date, is_recurring, rollover, rollover_limit,
        account_ids, category_ids, tag_ids, warning_pct, created_at, updated_at)
     VALUES (?,?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))`,
    [
      b.id,
      b.ledgerId,
      b.groupId ?? null,
      b.name,
      b.type,
      b.amount,
      b.saved ?? 0,
      b.frequency,
      b.startDate,
      b.endDate ?? null,
      b.isRecurring ?? (b.type === 'income' ? 0 : 1),
      b.rollover ?? 0,
      b.rolloverLimit ?? null,
      idsToJson(b.accountIds),
      idsToJson(b.categoryIds),
      idsToJson(b.tagIds),
      b.warningPct ?? 80,
    ],
  );
}

export interface BudgetPatch {
  groupId?: string | null;
  name?: string;
  type?: BudgetType;
  amount?: number;
  frequency?: string;
  startDate?: string;
  endDate?: string | null;
  isRecurring?: number;
  rollover?: number;
  rolloverLimit?: number | null;
  accountIds?: string[];
  categoryIds?: string[];
  tagIds?: string[];
  warningPct?: number;
}

const BUDGET_PATCH_COLUMNS: Record<keyof BudgetPatch, string> = {
  groupId: 'group_id',
  name: 'name',
  type: 'type',
  amount: 'amount',
  frequency: 'frequency',
  startDate: 'start_date',
  endDate: 'end_date',
  isRecurring: 'is_recurring',
  rollover: 'rollover',
  rolloverLimit: 'rollover_limit',
  accountIds: 'account_ids',
  categoryIds: 'category_ids',
  tagIds: 'tag_ids',
  warningPct: 'warning_pct',
};

const ARRAY_PATCH_KEYS: ReadonlySet<keyof BudgetPatch> = new Set(['accountIds', 'categoryIds', 'tagIds']);

export async function updateBudget(exec: Exec, id: string, patch: BudgetPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof BudgetPatch)[]) {
    const value = patch[key];
    if (value === undefined) continue;
    sets.push(`${BUDGET_PATCH_COLUMNS[key]} = ?`);
    if (ARRAY_PATCH_KEYS.has(key)) bind.push(idsToJson(value as string[]));
    else bind.push(value as string | number | null);
  }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE budgets SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Add to (or subtract from) an income/goal budget's manual `saved`, clamped at 0. */
export async function contributeBudget(exec: Exec, id: string, amount: number): Promise<void> {
  await exec(
    "UPDATE budgets SET saved = MAX(0, saved + ?), updated_at = datetime('now') WHERE id = ?",
    [amount, id],
  );
}

/** Hard-delete a named budget. */
export async function deleteBudget(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM budgets WHERE id = ?', [id]);
}
