import { NextResponse } from 'next/server';
import { I18nError, toWireError } from '@/lib/i18n-error';

// The one error shape every API route sends: `{ error: { message, code?, params? } }`.

/** A thrown error as a response. An I18nError is the engine refusing a request
 *  (unknown action, duplicate, a missing field…): 400. Anything else is a fault
 *  on our side: 500. Pass `status` to override. */
export function errorResponse(err: unknown, status?: number): NextResponse {
  return NextResponse.json(
    { error: toWireError(err) },
    { status: status ?? (err instanceof I18nError ? 400 : 500) },
  );
}

/** A plain message as a response, for errors the route itself detects. */
export function errorMessage(message: string, status: number): NextResponse {
  return NextResponse.json({ error: { message } }, { status });
}
