import { exportDbBytes } from '@/lib/db/server';

// Streams the authoritative server DB file so the downloaded copy is the live
// data (not a rebuild from the store cache).
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const bytes = await exportDbBytes();
  return new Response(bytes as BodyInit, {
    headers: {
      'Content-Type': 'application/x-sqlite3',
      'Content-Disposition': 'attachment; filename="finch.sqlite3"',
    },
  });
}
