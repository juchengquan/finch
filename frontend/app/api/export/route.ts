import { exportDbBytes } from '@/lib/db/server';

// Streams a stamped copy of the authoritative server DB. Metadata
// (exported_at, exported_from, row_counts, checksum) is applied to a clone so
// the live DB never carries stale "exported at X" stamps.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const { bytes, filename } = await exportDbBytes();
  return new Response(bytes as BodyInit, {
    headers: {
      'Content-Type': 'application/x-sqlite3',
      'Content-Disposition': `attachment; filename="${filename}"`,
    },
  });
}
