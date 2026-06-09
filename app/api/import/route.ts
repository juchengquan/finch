import { NextResponse } from 'next/server';
import { importDbBytes, importPackBytes } from '@/lib/db/core/server';
import { detectFileKind } from '@/lib/db/core/pack';

// Accepts a multipart upload with field name "file" — either:
//   - a bare .sqlite3 backup file, or
//   - a .finch zip pack (DB + receipts; PACK_FORMAT_PLAN §5).
//
// Routes by sniffing the first bytes ('PK\x03\x04' = zip,
// 'SQLite format 3\0' = bare DB). For the bare path, validation + autoBackup
// + atomic swap go through importDbBytes (back-compat). For the pack path,
// importPackBytes additionally extracts the pack to a staging dir, validates
// per-file sha256s, and atomically swaps both the DB AND the attachments
// folder.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  try {
    const form = await req.formData();
    const file = form.get('file');
    if (!(file instanceof File)) {
      return NextResponse.json({ error: 'Missing "file" field' }, { status: 400 });
    }
    if (file.size === 0) {
      return NextResponse.json({ error: 'Uploaded file is empty' }, { status: 400 });
    }

    const bytes = new Uint8Array(await file.arrayBuffer());
    const kind = detectFileKind(bytes.subarray(0, 16));
    let result;
    if (kind === 'zip') {
      result = await importPackBytes(bytes);
    } else if (kind === 'sqlite') {
      result = await importDbBytes(bytes);
    } else {
      return NextResponse.json(
        { error: 'Unrecognised file — expected a Finch .sqlite3 backup or a .finch pack' },
        { status: 400 },
      );
    }
    return NextResponse.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Import failed';
    console.error('POST /api/import failed', err);
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
