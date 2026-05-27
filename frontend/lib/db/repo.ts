import type { Tx, PendingItem, RecurringTemplate, AccountOverride } from '@/lib/store';

// A minimal async query interface so the same logic works against the in-memory
// sqlite (oo1.DB) on the server and in tests.
export type SqlBind = (string | number | null)[];
export type Row = Record<string, unknown>;
export type Exec = (sql: string, bind?: SqlBind) => Promise<Row[]>;

// The slice of app state that is persisted / projected to and from the database
// (mirrors the Zustand store).
export interface PersistState {
  transactions: Tx[];
  pending: PendingItem[];
  budgetOverrides: Record<string, number>;
  accountOverrides: Record<string, AccountOverride>;
  verifiedExtra: string[];
  aliasExtra: Record<string, string[]>;
  recurring: RecurringTemplate[];
}
