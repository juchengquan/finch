import { getServerDb } from '@/lib/db/server';
import { transactionsCsv } from '@/lib/db/queries/export';

// Human-readable transactions export (CSV), built from the live server DB.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const { exec } = await getServerDb();
  const csv = await transactionsCsv(exec);
  return new Response(csv, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': 'attachment; filename="finch-transactions.csv"',
    },
  });
}
