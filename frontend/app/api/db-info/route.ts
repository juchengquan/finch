import { NextResponse } from 'next/server';
import { getServerDb } from '@/lib/db/server';
import { auditLedger, type DbAudit } from '@/lib/db/entries';
import { readMetadata } from '@/lib/db/queries/metadata';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const MAX_PROBLEMS = 50;

export interface DbInfoResponse {
  path: string;
  schemaVersion: string;
  audit: DbAudit;
}

export async function GET() {
  try {
    const { file, exec } = await getServerDb();
    const meta = await readMetadata(exec);
    const all = await auditLedger(exec);
    const body: DbInfoResponse = {
      path: file,
      schemaVersion: meta?.schemaVersion ?? 'unknown',
      audit: {
        problems: all.slice(0, MAX_PROBLEMS),
        problemCount: all.length,
        checkedAt: new Date().toISOString(),
      },
    };
    return NextResponse.json(body);
  } catch (err) {
    console.error('GET /api/db-info failed', err);
    return NextResponse.json({ error: 'Could not read db info' }, { status: 500 });
  }
}
