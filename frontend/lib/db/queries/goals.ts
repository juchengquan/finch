// Savings goals: list, plus create / contribute handled in lib/db/mutations.ts.

import type { Exec } from '@/lib/db/repo';

export interface Goal {
  id: string;
  ledgerId: string;
  name: string;
  target: number;
  saved: number;
  eta: string | null;
  hue: number;
}

/** List goals; pass a ledgerId to scope, or omit for all ledgers. */
export async function listGoals(exec: Exec, ledgerId?: string): Promise<Goal[]> {
  const rows = await exec(
    ledgerId
      ? 'SELECT * FROM goals WHERE ledger_id = ? ORDER BY sort_order'
      : 'SELECT * FROM goals ORDER BY ledger_id, sort_order',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    name: String(r.name),
    target: Number(r.target),
    saved: Number(r.saved),
    eta: r.eta == null ? null : String(r.eta),
    hue: Number(r.hue),
  }));
}

/** Hard delete a goal (no foreign keys reference it). */
export async function deleteGoal(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM goals WHERE id = ?', [id]);
}
