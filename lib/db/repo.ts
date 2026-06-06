import type { Tx, ScheduledTemplate } from '@/lib/store';
import type { AccountRow } from './queries/accounts';
import type { AccountGroupRow } from './queries/accountGroups';
import type { BudgetRow } from './queries/budgets';
import type { BudgetGroupRow } from './queries/budgetGroups';
import type { CategoryRow } from './queries/categories';
import type { Counterparty } from './queries/counterparties';
import type { LedgerRow } from './queries/ledgers';
import type { ExchangeRate } from './queries/system';
import type { Tag } from './queries/tags';
import type { Holding } from './queries/holdings';
import type { Attachment } from './queries/attachments';
import type { Rule } from '@/lib/rules/types';

// A minimal async query interface so the same logic works against the in-memory
// sqlite (oo1.DB) on the server and in tests.
export type SqlBind = (string | number | null)[];
export type Row = Record<string, unknown>;
export type Exec = (sql: string, bind?: SqlBind) => Promise<Row[]>;

// The slice of app state that is persisted / projected to and from the database
// (mirrors the Zustand store).
export interface PersistState {
  transactions: Tx[];
}

// What the server projects to the client: persisted slices + reference/derived
// data the read screens need (account balances, categories, merchants).
export interface ProjectedState extends PersistState {
  /** Live ledger rows. The UI merges these with the static `data/ledgers.json`
   *  for cosmetic fields (color/tagline) the schema doesn't store. */
  ledgers: LedgerRow[];
  accounts: AccountRow[];
  accountGroups: AccountGroupRow[];
  /** Named budgets (expense limits / income targets). */
  budgets: BudgetRow[];
  budgetGroups: BudgetGroupRow[];
  categories: CategoryRow[];
  counterparties: Counterparty[];
  exchangeRates: ExchangeRate[];
  tags: Tag[];
  /** Per-position investment holdings inside investment-type accounts. */
  holdings: Holding[];
  scheduled: ScheduledTemplate[];
  /** Conditional rules engine — per-ledger if-then rules consumed by
   *  applyRules() on insert. RULES_ENGINE_PLAN §2. */
  rules: Rule[];
  /** Receipt attachments — pointer rows; bytes live on the server
   *  filesystem and are reached via GET /api/attachments/:id.
   *  RECEIPT_PHOTOS_PLAN §2.1. */
  attachments: Attachment[];
  /** Ordered section ids for the mobile bottom bar. Empty = use the client default. */
  mobileTabIds: string[];
  /** Per-ledger display currency (ledgerId → currency). Missing = ledger's base. */
  displayCurrencyByLedger: Record<string, string>;
}
