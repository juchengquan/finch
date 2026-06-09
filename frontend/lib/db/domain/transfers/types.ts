// lib/db/domain/transfers/types.ts — public row + input/patch shapes for the
// transfers domain. Keep this file free of SQL imports — it should be safe
// to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface Transfer {
  id: string; // entry id (was transfer_group_id)
  date: string;
  /** Time-of-day "HH:MM" shared by both legs; null when none was recorded. */
  time: string | null;
  amount: number; // positive magnitude sent, in `fromCurrency` (native)
  toAmount: number; // positive magnitude received, in `toCurrency` (native)
  fromCurrency: string;
  toCurrency: string;
  fromAccountId: string | null;
  toAccountId: string | null;
  fromName: string | null;
  toName: string | null;
  note: string | null;
}

export interface TransferPatch {
  /** Sent magnitude, in the from-account's currency. */
  fromAmount?: number;
  /** Received magnitude, in the to-account's currency. Set this when the
   *  bank's actual conversion differs from the mid-rate; the effective FX
   *  rate becomes `toAmount / fromAmount`. */
  toAmount?: number;
  date?: string;
  /** Time-of-day "HH:MM" written to both legs; null clears it. */
  time?: string | null;
  note?: string | null;
}
