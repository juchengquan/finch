// lib/db/domain/_shared/post-helpers.ts — small helpers for posting single
// transactions and transfers that mutations.ts uses for scheduled/recurring.
import { postSimple } from '../../core/entries';
import type { Exec } from '../../core/repo';

export async function postSingle(
  exec: Exec,
  ledgerId: string,
  accountId: string,
  amount: number,
  description: string,
  date: string,
  sourceTemplateId: string | null = null,
  categoryId: string | null = null,
  occurrenceDate: string | null = null,
  time: string | null = null,
): Promise<void> {
  await postSimple(exec, {
    ledgerId, accountId, date, time,
    amount, description, categoryId,
    kind: amount > 0 ? 'income' : 'expense',
    sourceTemplateId, occurrenceDate,
  });
}
