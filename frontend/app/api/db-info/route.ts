import { NextResponse } from 'next/server';
import { getServerDb, getCachedAudit } from '@/lib/db/core/server';
import type { DbAudit } from '@/lib/db/core/entries';
import { readMetadata } from '@/lib/db/queries/metadata';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export interface DbInfoResponse {
  path: string;
  schemaVersion: string;
  audit: DbAudit;
}

export async function GET() {
  try {
    const { file, exec } = await getServerDb();
    const meta = await readMetadata(exec);
    const body: DbInfoResponse = {
      path: file,
      schemaVersion: meta?.schemaVersion ?? 'unknown',
      audit: await getCachedAudit(),
    };
    return NextResponse.json(body);
  } catch (err) {
    console.error('GET /api/db-info failed', err);
    return NextResponse.json({ error: 'Could not read db info' }, { status: 500 });
  }
}
