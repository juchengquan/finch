import { NextResponse } from 'next/server';
import { readState } from '@/lib/db/core/server';
import { errorMessage } from '@/lib/api-error';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Full app state, projected from the server database.
export async function GET() {
  try {
    const state = await readState();
    return NextResponse.json(state);
  } catch (err) {
    console.error('GET /api/state failed', err);
    return errorMessage('Could not read state', 500);
  }
}
