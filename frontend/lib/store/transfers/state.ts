// frontend/lib/store/transfers/state.ts — transfers-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in transfers/actions.ts. Note: transfers aren't a separate top-level
// state key — they live inside `transactions` as two rows sharing a
// `transferGroupId` — so this slice is intentionally empty for now.
//
// Also owns the TransferInput data type that was previously declared in
// lib/store.ts:70-85. Re-exported from lib/store/index.ts so the existing
// `import type { TransferInput } from '@/lib/store'` paths keep working
// during the migration.

export interface TransferInput {
  fromAccountId: string;
  toAccountId: string;
  /** Sent magnitude, in the from-account's currency. */
  fromAmount: number;
  /** Optional received magnitude, in the to-account's currency. When omitted,
   *  derived from the rates table at `date`. Set this to pin both sides
   *  (e.g. matching a bank statement where the actual conversion differs
   *  from the mid-rate); the rate becomes `toAmount / fromAmount`. */
  toAmount?: number;
  date: string;
  /** Time-of-day "HH:MM" stamped on both legs, mirroring a normal entry. When
   *  omitted the legs carry a null time (e.g. scheduled posts). */
  time?: string;
  note?: string;
}

export const transfersInitial = {} as const;
