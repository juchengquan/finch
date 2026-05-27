// Read queries for the Subscriptions and Scheduled screens.

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

export interface ScheduledItem {
  id: string;
  ledgerId: string;
  day: number;
  month: string;
  label: string;
  amount: number;
  type: string;
  color: string | null;
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

export async function listScheduledItems(exec: Exec, ledgerId?: string): Promise<ScheduledItem[]> {
  const rows = await exec(
    ledgerId ? 'SELECT * FROM scheduled_items WHERE ledger_id = ?' : 'SELECT * FROM scheduled_items',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    day: Number(r.day),
    month: String(r.month),
    label: String(r.label),
    amount: Number(r.amount),
    type: String(r.type),
    color: r.color == null ? null : String(r.color),
  }));
}
