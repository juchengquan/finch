import { NextResponse } from 'next/server';
import { autoBackup, listBackups } from '@/lib/db/server';

// GET  /api/backups  — list existing on-disk backups (path + name + size +
//                      createdAt), newest first.
// POST /api/backups  — trigger autoBackup() (respects throttle); returns the
//                      path it wrote / reused.

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const backups = await listBackups();
    return NextResponse.json({ backups });
  } catch (err) {
    console.error('GET /api/backups failed', err);
    return NextResponse.json({ error: 'Could not list backups' }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    let force = false;
    try {
      const body = (await req.json().catch(() => ({}))) as { force?: boolean };
      force = !!body.force;
    } catch {
      // empty body — treat as throttled call
    }
    // User-pressed "Backup now" forces a snapshot regardless of throttle or
    // "off" setting; a routine call respects both.
    const result = await autoBackup(force ? { force: true } : undefined);
    return NextResponse.json(result);
  } catch (err) {
    console.error('POST /api/backups failed', err);
    return NextResponse.json({ error: 'Backup failed' }, { status: 500 });
  }
}
