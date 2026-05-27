import type { Tx, RecurringTemplate, AccountOverride } from '@/lib/store';
import type { AccountRow } from './queries/accounts';
import type { CategoryRow } from './queries/categories';
import type { Counterparty } from './queries/counterparties';
import type { ExchangeRate, Device } from './queries/system';
import type { Goal } from './queries/goals';
import type { Tag } from './queries/tags';

// A minimal async query interface so the same logic works against the in-memory
// sqlite (oo1.DB) on the server and in tests.
export type SqlBind = (string | number | null)[];
export type Row = Record<string, unknown>;
export type Exec = (sql: string, bind?: SqlBind) => Promise<Row[]>;

// The slice of app state that is persisted / projected to and from the database
// (mirrors the Zustand store).
export interface PersistState {
  transactions: Tx[];
  budgetOverrides: Record<string, number>;
  accountOverrides: Record<string, AccountOverride>;
  verifiedExtra: string[];
  aliasExtra: Record<string, string[]>;
  recurring: RecurringTemplate[];
}

// What the server projects to the client: persisted slices + reference/derived
// data the read screens need (account balances, categories, merchants).
export interface ProjectedState extends PersistState {
  accounts: AccountRow[];
  categories: CategoryRow[];
  counterparties: Counterparty[];
  exchangeRates: ExchangeRate[];
  devices: Device[];
  goals: Goal[];
  tags: Tag[];
}
