import { getServerDb } from '@/lib/db/core/server';
import { transactionsCsv } from '@/lib/db/domain/_app/export';

// Human-readable transactions export (CSV), built from the live server DB.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Optional `?ledger=<id>&month=YYYY-MM` scopes the export (used by the Insights
// Breakdown view); omitting both yields the full all-ledgers dump (Settings).
export async function GET(req: Request) {
  const { exec } = await getServerDb();
  const url = new URL(req.url);
  const ledgerId = url.searchParams.get('ledger') ?? undefined;
  const month = url.searchParams.get('month') ?? undefined;
  const csv = await transactionsCsv(exec, { ledgerId, month });
  const suffix = [ledgerId, month].filter(Boolean).join('-');
  const filename = suffix ? `finch-transactions-${suffix}.csv` : 'finch-transactions.csv';
  return new Response(csv, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${filename}"`,
    },
  });
}
