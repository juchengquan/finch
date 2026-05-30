import { NextResponse } from 'next/server';
import { importDbBytes } from '@/lib/db/server';

// Accepts a multipart upload with field name "file" (the .sqlite3 backup).
// Validates against the file format + schema + checksum, snapshots the live
// DB via autoBackup, then atomically swaps the file in place. The next
// request reopens against the new bytes.
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
    const result = await importDbBytes(bytes);
    return NextResponse.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Import failed';
    console.error('POST /api/import failed', err);
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
