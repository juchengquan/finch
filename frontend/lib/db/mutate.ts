// lib/db/mutate.ts — the thin dispatch layer that replaces the
// 1426-line mutations.ts. Each per-domain mutations module exports a
// `handlers` map; this file merges them into one ALL map and dispatches
// by action name.
//
// Wire contract (preserved bit-for-bit from the old mutations.ts):
//   applyMutation(exec, action, args): Promise<void>

import type { Exec } from './core/repo';
import type { Args, ActionName } from './domain/_args';
import { I18nError } from '@/lib/i18n-error';

import { handlers as accountsHandlers } from './domain/accounts/mutations';
import { handlers as transactionsHandlers } from './domain/transactions/mutations';
import { handlers as budgetsHandlers } from './domain/budgets/mutations';
import { handlers as categoriesHandlers } from './domain/categories/mutations';
import { handlers as counterpartiesHandlers } from './domain/counterparties/mutations';
import { handlers as tagsHandlers } from './domain/tags/mutations';
import { handlers as rulesHandlers } from './domain/rules/mutations';
import { handlers as scheduledHandlers } from './domain/scheduled/mutations';
import { handlers as transfersHandlers } from './domain/transfers/mutations';
import { handlers as holdingsHandlers } from './domain/holdings/mutations';
import { handlers as ledgersHandlers } from './domain/ledgers/mutations';
import { handlers as accountGroupsHandlers } from './domain/accountGroups/mutations';
import { handlers as appHandlers } from './domain/_app/mutations';

const ALL = {
  ...accountsHandlers,
  ...transactionsHandlers,
  ...budgetsHandlers,
  ...categoriesHandlers,
  ...counterpartiesHandlers,
  ...tagsHandlers,
  ...rulesHandlers,
  ...scheduledHandlers,
  ...transfersHandlers,
  ...holdingsHandlers,
  ...ledgersHandlers,
  ...accountGroupsHandlers,
  ...appHandlers,
} satisfies { [K in ActionName]: (exec: Exec, args: Args[K]) => Promise<void> };

export async function applyMutation(
  exec: Exec,
  action: string,
  args: Record<string, unknown>,
): Promise<void> {
  const handler = ALL[action as ActionName];
  if (!handler) {
    throw new I18nError('error.unknownAction', { action }, `Unknown action "${action}"`);
  }
  await handler(exec, args as never);
}
