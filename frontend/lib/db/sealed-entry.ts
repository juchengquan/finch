// lib/db/sealed-entry.ts — manual sealed-entry insert + residue append.
//
// This module is the two-phase write path used by seed.ts to populate the
// canonical schema with sealed entries. It deliberately bypasses postEntry:
//   - postEntry re-fires the rules engine, resolves counterparties, and may
//     re-derive exchange rates. Sealed inserts must preserve figures verbatim.
//   - This path does INSERT entries (sealed=0), INSERT postings, then UPDATE
//     entries SET sealed=1, which fires the balance-check trigger (I1/I2).
//     Same two-phase write, no rules/counterparty overhead.
//
// MoveLeg / MoveHeader are exported so seed.ts can be a second consumer
// without re-implementing the shape.

import type { Exec } from '@/lib/db/repo';
import { dedupHash } from './entries';

const r2 = (n: number) => Math.round(n * 100) / 100;

export interface MoveLeg {
  id: string;
  accountId: string | null;
  categoryId: string | null;
  amount: number;
  currency: string;
  amountBase: number;
  exchangeRate: number;
  origAmount: number | null;
  origCurrency: string | null;
  description?: string | null;
  memo: string | null;
  clearedAt: string | null;
}

export interface MoveHeader {
  id: string;
  ledgerId: string;
  date: string;
  time: string | null;
  description: string | null;
  kind: string;
  status: string;
  confirmedAt: string | null;
  counterpartyId: string | null;
  refundedEntryId: string | null;
  sourceTemplateId: string | null;
  notes: string | null;
  appliedRuleIds: string | null;
  reviewedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

/** Insert an entry (sealed=0), its postings, then seal it (fires the
 *  balance-check trigger). No savepoint — the dedup hash + end audit are
 *  the safety net. */
export async function insertSealedEntry(exec: Exec, hdr: MoveHeader, legs: MoveLeg[]): Promise<void> {
  const hash = dedupHash(hdr.date, hdr.time, hdr.description ?? '', legs);
  await exec(
    `INSERT INTO entries
       (id,ledger_id,date,time,description,kind,status,confirmed_at,
        counterparty_id,refunded_entry_id,source_template_id,notes,
        applied_rule_ids,reviewed_at,dedup_hash,sealed,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?)`,
    [
      hdr.id, hdr.ledgerId, hdr.date, hdr.time, hdr.description,
      hdr.kind, hdr.status, hdr.confirmedAt,
      hdr.counterpartyId, hdr.refundedEntryId, hdr.sourceTemplateId, hdr.notes,
      hdr.appliedRuleIds, hdr.reviewedAt, hash,
      hdr.createdAt, hdr.updatedAt,
    ],
  );
  for (let i = 0; i < legs.length; i++) {
    const l = legs[i];
    await exec(
      `INSERT INTO postings
         (id,entry_id,account_id,category_id,amount,currency,amount_base,
          exchange_rate,orig_amount,orig_currency,memo,cleared_at,sort_order)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        l.id, hdr.id, l.accountId, l.categoryId,
        l.amount, l.currency, l.amountBase, l.exchangeRate,
        l.origAmount, l.origCurrency, l.memo, l.clearedAt, i,
      ],
    );
  }
  await exec('UPDATE entries SET sealed = 1 WHERE id = ?', [hdr.id]);
}

/** Append an FX residue leg when Σ amountBase is not zero (§5.1 / I1).
 *  Threshold 0.005 — same as postEntry's appendResidue. */
export function appendResidueIfNeeded(legs: MoveLeg[], fxCategoryId: string, base: string, entryId: string): void {
  const residue = r2(legs.reduce((s, l) => s + l.amountBase, 0));
  if (Math.abs(residue) >= 0.005) {
    legs.push({
      id: `${entryId}-fx`,
      accountId: null,
      categoryId: fxCategoryId,
      amount: r2(-residue),
      currency: base,
      amountBase: r2(-residue),
      exchangeRate: 1,
      origAmount: null,
      origCurrency: null,
      memo: null,
      clearedAt: null,
    });
  }
}
