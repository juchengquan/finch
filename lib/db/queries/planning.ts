// Read queries for the Subscriptions screen.

import type { Exec } from '@/lib/db/repo';

export interface Subscription {
  id: string;
  ledgerId: string;
  name: string;
  amount: number;
  cadence: string;
  next: string | null;
  hue: number;
}

export async function listSubscriptions(exec: Exec, ledgerId?: string): Promise<Subscription[]> {
  const rows = await exec(
    ledgerId ? 'SELECT * FROM subscriptions WHERE ledger_id = ? ORDER BY sort_order' : 'SELECT * FROM subscriptions ORDER BY ledger_id, sort_order',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    name: String(r.name),
    amount: Number(r.amount),
    cadence: String(r.cadence),
    next: r.next_date == null ? null : String(r.next_date),
    hue: Number(r.hue),
  }));
}

export interface SubscriptionPatch {
  name?: string;
  amount?: number;
  cadence?: string;
  next?: string | null;
}

/** Update a subscription's editable fields. */
export async function updateSubscription(exec: Exec, id: string, patch: SubscriptionPatch): Promise<void> {
  const cols: Record<keyof SubscriptionPatch, string> = { name: 'name', amount: 'amount', cadence: 'cadence', next: 'next_date' };
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  for (const key of Object.keys(patch) as (keyof SubscriptionPatch)[]) {
    if (patch[key] === undefined) continue;
    sets.push(`${cols[key]} = ?`);
    bind.push(patch[key] ?? null);
  }
  if (!sets.length) return;
  bind.push(id);
  await exec(`UPDATE subscriptions SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Hard delete a subscription (no foreign keys reference it). */
export async function deleteSubscription(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM subscriptions WHERE id = ?', [id]);
}

