import { NextResponse } from 'next/server';
import { readState } from '@/lib/db/core/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Full app state, projected from the server database.
export async function GET() {
  try {
    const state = await readState();
    return NextResponse.json(state);
  } catch (err) {
    console.error('GET /api/state failed', err);
    return NextResponse.json({ error: 'Could not read state' }, { status: 500 });
  }
}
