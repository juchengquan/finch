import { NextResponse } from 'next/server';
import { withDb } from '@/lib/db/core/server';
import { readMetadata, rowCounts } from '@/lib/db/domain/_app/metadata';
import { errorMessage } from '@/lib/api-error';

// Returns the db_metadata row (provenance + version + row counts) so the UI can
// show "schema vX · Y transactions · last exported on Z" without downloading
// the whole file.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const [meta, counts] = await withDb(({ exec }) => Promise.all([readMetadata(exec), rowCounts(exec)]));
    if (!meta) {
      return errorMessage('No metadata row', 500);
    }
    return NextResponse.json({ ...meta, rowCounts: counts });
  } catch (err) {
    console.error('GET /api/export/metadata failed', err);
    return errorMessage('Could not read metadata', 500);
  }
}
