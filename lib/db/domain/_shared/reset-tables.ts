// lib/db/domain/_shared/reset-tables.ts — the list of tables the 'reset'
// mutation truncates, and the resetDb function. Order matters (children
// before parents) because foreign keys are RESTRICT.
import { seedReference, insertTransactions, seedTransactionTags } from '../../core/seed';
import transactionsData from '@/data/transactions.json';
import type { Tx } from '@/lib/store';
import type { Exec } from '../../core/repo';

const RESET_TABLES = [
  'holdings',
  'entry_attachments',
  'entry_tags',
  'postings',
  'entries',
  'scheduled_splits',
  'scheduled_templates',
  'tags',
  'budgets',
  'budget_groups',
  'counterparties',
  'transfers',
  'categories',
  'accounts',
  'account_groups',
  'exchange_rates',
  'rules',
  'ledgers',
  'app_state',
];

export async function resetDb(exec: Exec): Promise<void> {
  for (const t of RESET_TABLES) await exec(`DELETE FROM ${t}`);
  await seedReference(exec);
  await insertTransactions(exec, transactionsData as Tx[]);
  await seedTransactionTags(exec);
}
