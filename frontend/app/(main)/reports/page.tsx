import { redirect } from 'next/navigation';

// Reports were merged into Insights as the "Breakdown" view — there is no
// standalone Reports screen. Old links/bookmarks land on Insights (the
// Breakdown tab there shows the per-category monthly spend + CSV export).
export default function ReportsPage() {
  redirect('/insights');
}
