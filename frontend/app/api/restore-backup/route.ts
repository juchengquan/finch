import { NextResponse } from 'next/server';
import { restoreBackup } from '@/lib/db/core/server';

// Swap the live DB with the contents of one of the on-disk backups listed by
// GET /api/backups. Runs through the same validation + autoBackup + swap as
// /api/import, so the prior live state is preserved as a fresh backup before
// the restore takes effect.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  try {
    const body = (await req.json().catch(() => ({}))) as { name?: string };
    if (!body.name) {
      return NextResponse.json({ error: 'Missing "name"' }, { status: 400 });
    }
    const result = await restoreBackup(body.name);
    return NextResponse.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Restore failed';
    console.error('POST /api/restore-backup failed', err);
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
