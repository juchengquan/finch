import { NextResponse } from 'next/server';
import { withWrite } from '@/lib/db/server';
import { applyMutation } from '@/lib/db/mutations';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type Body = { action: string; args?: Record<string, unknown> };

// One write endpoint. Each action runs SQL against the authoritative server DB
// (the DB's triggers maintain balances/summaries); the new full state is
// returned so the client can refresh its cache.
export async function POST(req: Request) {
  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }
  if (!body?.action) return NextResponse.json({ error: 'Missing action' }, { status: 400 });
  try {
    const state = await withWrite((exec) => applyMutation(exec, body.action, body.args ?? {}));
    return NextResponse.json(state);
  } catch (err) {
    console.error(`POST /api/mutate (${body.action}) failed`, err);
    return NextResponse.json({ error: String((err as Error).message ?? err) }, { status: 500 });
  }
}
