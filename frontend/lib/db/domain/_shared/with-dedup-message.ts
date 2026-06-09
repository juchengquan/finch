// lib/db/domain/_shared/with-dedup-message.ts — wrap a DB operation to
// translate a UNIQUE-violation error into a localized I18nError. Lives
// in _shared/ because the dedup indices (entries, budgets) cross
// domain boundaries.
import { I18nError } from '@/lib/i18n-error';

const DEDUP_MESSAGES: { signature: string; code: string; message: string }[] = [
  { signature: 'entries.ledger_id, entries.dedup_hash', code: 'error.duplicate.txn', message: 'This looks like a duplicate — an identical transaction already exists.' },
  { signature: 'budgets.ledger_id, budgets.name', code: 'error.duplicate.budget', message: 'A budget with this name and cycle already exists.' },
];

export async function withDedupMessage<T>(run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (err) {
    const msg = String((err as Error)?.message ?? err);
    if (msg.includes('UNIQUE constraint failed')) {
      for (const { signature, code, message } of DEDUP_MESSAGES) {
        if (msg.includes(signature)) throw new I18nError(code, {}, message);
      }
    }
    throw err;
  }
}
