import { NextResponse } from 'next/server';
import { getServerDb } from '@/lib/db/core/server';
import { listArchivedAccounts } from '@/lib/db/queries/accounts';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  try {
    const { exec } = await getServerDb();
    const url = new URL(req.url);
    const ledgerId = url.searchParams.get('ledgerId') ?? undefined;
    const rows = await listArchivedAccounts(exec, ledgerId ?? undefined);
    return NextResponse.json(rows);
  } catch (err) {
    console.error('GET /api/accounts/archived failed', err);
    return NextResponse.json({ error: 'Could not list archived accounts' }, { status: 500 });
  }
}
