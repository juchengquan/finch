import { exportDbBytes, exportPackBytes } from '@/lib/db/core/server';

// Streams a stamped copy of the authoritative server DB. Two formats:
//   - default                        -> bare .sqlite3 file (back-compat)
//   - ?withAttachments=true|1|yes    -> .finch zip pack (PACK_FORMAT_PLAN §4)
//                                       carrying the DB + every receipt
//                                       attachment + an integrity manifest
//
// Metadata (exported_at, exported_from, row_counts, checksum) is applied to a
// clone so the live DB never carries stale "exported at X" stamps.

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function truthy(v: string | null): boolean {
  if (!v) return false;
  const s = v.toLowerCase();
  return s === '1' || s === 'true' || s === 'yes' || s === 'on';
}

export async function GET(req: Request) {
  const url = new URL(req.url);
  const withAttachments = truthy(url.searchParams.get('withAttachments'));

  if (withAttachments) {
    const { bytes, filename } = await exportPackBytes();
    return new Response(bytes as BodyInit, {
      headers: {
        'Content-Type': 'application/zip',
        'Content-Disposition': `attachment; filename="${filename}"`,
        'Cache-Control': 'private, max-age=0, must-revalidate',
      },
    });
  }

  const { bytes, filename } = await exportDbBytes();
  return new Response(bytes as BodyInit, {
    headers: {
      'Content-Type': 'application/x-sqlite3',
      'Content-Disposition': `attachment; filename="${filename}"`,
    },
  });
}
