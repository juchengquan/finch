// frontend/lib/store/state.ts — the FinanceState interface (state only).
// Moved from lib/store.ts:188-374 (PR #131). The action types live in
// per-domain actions.ts files (PR #131, Tasks 4-7).
//
// Import path notes:
// - `Tx` and `ScheduledTemplate` now live in their owning per-domain state
//   files (transactions/state.ts and scheduled/state.ts respectively) and
//   are re-exported from lib/store/index.ts so the existing
//   `import type { Tx } from '@/lib/store'` paths keep working.
// - The DB row types come from `lib/db/domain/<x>/types` (the post-refactor
//   per-domain types layer), matching the imports lib/store.ts:7-18 uses today.

import type { AccountRow } from '@/lib/db/domain/accounts/types';
import type { AccountGroupRow } from '@/lib/db/domain/accountGroups/types';
import type { BudgetRow } from '@/lib/db/domain/budgets/types';
import type { BudgetGroupRow } from '@/lib/db/domain/budgetGroups/types';
import type { CategoryRow } from '@/lib/db/domain/categories/types';
import type { Counterparty } from '@/lib/db/domain/counterparties/types';
import type { LedgerRow } from '@/lib/db/domain/ledgers/types';
import type { ExchangeRate } from '@/lib/db/domain/_app/system.types';
import type { Tag } from '@/lib/db/domain/tags/types';
import type { Holding } from '@/lib/db/domain/holdings/types';
import type { Attachment } from '@/lib/db/domain/attachments/types';
import type { Rule } from '@/lib/rules/types';
import type { Tx } from './transactions/state';
import type { ScheduledTemplate } from './scheduled/state';

export interface FinanceState {
  transactions: Tx[];
  scheduled: ScheduledTemplate[];
  // Reference / derived data projected from the server DB (read-only mirror).
  ledgers: LedgerRow[];
  accounts: AccountRow[];
  accountGroups: AccountGroupRow[];
  budgets: BudgetRow[];
  budgetGroups: BudgetGroupRow[];
  categories: CategoryRow[];
  counterparties: Counterparty[];
  exchangeRates: ExchangeRate[];
  tags: Tag[];
  /** Per-position investment holdings inside investment-type accounts. */
  holdings: Holding[];
  /** Conditional rules engine — per-ledger if-then rules consumed by
   *  applyRules() on insert. See RULES_ENGINE_PLAN §2. */
  rules: Rule[];
  /** Receipt attachments — pointer rows. The actual photos/PDFs live on
   *  the server filesystem and are reached via GET /api/attachments/:id.
   *  RECEIPT_PHOTOS_PLAN §2.1. */
  attachments: Attachment[];
  /** Ordered section ids for the mobile bottom bar (empty = client default). */
  mobileTabIds: string[];
  /** Per-ledger display currency (ledgerId → currency). Missing = ledger's base. */
  displayCurrencyByLedger: Record<string, string>;
  /** Auto-backup frequency + retention. Persisted in app_state, mirrored here.
   *  frequencyMs: -1 = off, 0 = every change, >0 = minimum interval (ms).
   *  retention: number of `.finch.bak` files to keep on disk. */
  backupConfig: { frequencyMs: number; retention: number };
}
