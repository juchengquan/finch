import { NextResponse } from 'next/server';
import { getServerDb } from '@/lib/db/core/server';
import { readMetadata, rowCounts } from '@/lib/db/queries/metadata';

// Returns the db_metadata row (provenance + version + row counts) so the UI can
// show "schema vX · Y transactions · last exported on Z" without downloading
// the whole file.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const { exec } = await getServerDb();
    const [meta, counts] = await Promise.all([readMetadata(exec), rowCounts(exec)]);
    if (!meta) {
      return NextResponse.json({ error: 'No metadata row' }, { status: 500 });
    }
    return NextResponse.json({ ...meta, rowCounts: counts });
  } catch (err) {
    console.error('GET /api/export/metadata failed', err);
    return NextResponse.json({ error: 'Could not read metadata' }, { status: 500 });
  }
}
