import { NextResponse } from 'next/server';
import { getServerDb } from '@/lib/db/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Where the server is persisting the database (shown read-only in Settings).
export async function GET() {
  try {
    const { file } = await getServerDb();
    return NextResponse.json({ path: file });
  } catch (err) {
    console.error('GET /api/db-info failed', err);
    return NextResponse.json({ error: 'Could not read db info' }, { status: 500 });
  }
}
