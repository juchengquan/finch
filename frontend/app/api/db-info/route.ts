import { NextResponse } from 'next/server';
import { withDb, getCachedAudit } from '@/lib/db/core/server';
import type { DbAudit } from '@/lib/db/core/entries';
import { readMetadata } from '@/lib/db/domain/_app/metadata';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export interface DbInfoResponse {
  path: string;
  schemaVersion: string;
  audit: DbAudit;
}

export async function GET() {
  try {
    const { file, meta } = await withDb(async ({ file, exec }) => ({ file, meta: await readMetadata(exec) }));
    const body: DbInfoResponse = {
      path: file,
      schemaVersion: meta?.schemaVersion ?? 'unknown',
      audit: await getCachedAudit(), // takes the lock itself — keep outside withDb
    };
    return NextResponse.json(body);
  } catch (err) {
    console.error('GET /api/db-info failed', err);
    return NextResponse.json({ error: 'Could not read db info' }, { status: 500 });
  }
}
