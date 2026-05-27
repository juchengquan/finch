import { NextResponse } from 'next/server';
import { withWrite } from '@/lib/db/server';
import type { Exec } from '@/lib/db/repo';
import {
  addTransaction,
  updateTransaction,
  cancelTransaction,
  confirmTransaction,
  type AddInput,
} from '@/lib/db/queries/transactions';
import { setAccountDetails } from '@/lib/db/queries/accounts';
import { verifyCounterparty, addAlias } from '@/lib/db/queries/counterparties';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type Body = { action: string; args?: Record<string, unknown> };

// One write endpoint. Each action runs SQL against the authoritative server DB;
// the DB's triggers maintain balances/summaries; the new full state is returned
// so the client can refresh its cache.
async function apply(action: string, args: Record<string, unknown>, exec: Exec): Promise<void> {
  switch (action) {
    case 'addTransaction':
      await addTransaction(exec, args as unknown as AddInput);
      return;
    case 'updateTransaction':
      await updateTransaction(exec, String(args.id), args.patch as Parameters<typeof updateTransaction>[2]);
      return;
    case 'cancelTransaction':
      await cancelTransaction(exec, String(args.id));
      return;
    case 'confirmTransaction':
      await confirmTransaction(exec, String(args.id));
      return;
    case 'setAccountDetails':
      await setAccountDetails(exec, String(args.id), args.patch as Parameters<typeof setAccountDetails>[2]);
      return;
    case 'verifyCounterparty':
      await verifyCounterparty(exec, String(args.id));
      return;
    case 'addAlias':
      await addAlias(exec, String(args.id), String(args.alias));
      return;
    default:
      throw new Error(`Unknown action: ${action}`);
  }
}

export async function POST(req: Request) {
  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }
  if (!body?.action) return NextResponse.json({ error: 'Missing action' }, { status: 400 });
  try {
    const state = await withWrite((exec) => apply(body.action, body.args ?? {}, exec));
    return NextResponse.json(state);
  } catch (err) {
    console.error(`POST /api/mutate (${body.action}) failed`, err);
    return NextResponse.json({ error: String((err as Error).message ?? err) }, { status: 500 });
  }
}
