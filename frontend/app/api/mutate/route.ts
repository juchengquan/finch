import { NextResponse } from 'next/server';
import { withWrite } from '@/lib/db/core/server';
import { applyMutation } from '@/lib/db/mutate';
import { errorMessage, errorResponse } from '@/lib/api-error';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

type Body = { action: string; args?: Record<string, unknown> };

// One write endpoint. Each action runs SQL against the authoritative server DB
// (the DB's triggers maintain balances/summaries); the new full state is
// returned so the client can refresh its cache.
//
// Errors are `{ error: { message, code?, params? } }` (lib/api-error.ts). A
// refusal from the engine (an I18nError: unknown action, duplicate, a missing
// field) is a 400; anything else is a 500.
export async function POST(req: Request) {
  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return errorMessage('Invalid JSON', 400);
  }
  if (typeof body?.action !== 'string' || !body.action) return errorMessage('Missing action', 400);
  try {
    const state = await withWrite((exec) => applyMutation(exec, body.action, body.args ?? {}));
    return NextResponse.json(state);
  } catch (err) {
    console.error(`POST /api/mutate (${body.action}) failed`, err);
    return errorResponse(err);
  }
}
