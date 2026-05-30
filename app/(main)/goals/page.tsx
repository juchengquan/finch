import { redirect } from 'next/navigation';

// Goals are merged into Budgets as the "income" type — there is no standalone
// Goals screen. Old links/bookmarks land on Budgets (use the Income tab there).
export default function GoalsPage() {
  redirect('/budgets');
}
