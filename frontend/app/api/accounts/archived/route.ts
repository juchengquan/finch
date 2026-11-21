import { NextResponse } from 'next/server';
import { withDb } from '@/lib/db/core/server';
import { listArchivedAccounts } from '@/lib/db/domain/accounts/queries';
import { errorMessage } from '@/lib/api-error';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  try {
    const url = new URL(req.url);
    const ledgerId = url.searchParams.get('ledgerId') ?? undefined;
    const rows = await withDb(({ exec }) => listArchivedAccounts(exec, ledgerId));
    return NextResponse.json(rows);
  } catch (err) {
    console.error('GET /api/accounts/archived failed', err);
    return errorMessage('Could not list archived accounts', 500);
  }
}
