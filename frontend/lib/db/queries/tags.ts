// Tags: list, plus the transaction→tags map. Create / assign in mutations.ts.

import type { Exec } from '@/lib/db/repo';

export interface Tag {
  id: string;
  ledgerId: string;
  name: string;
  color: string | null;
}

/** List tags; pass a ledgerId to scope, or omit for all ledgers. */
export async function listTags(exec: Exec, ledgerId?: string): Promise<Tag[]> {
  const rows = await exec(
    ledgerId ? 'SELECT * FROM tags WHERE ledger_id = ? ORDER BY name' : 'SELECT * FROM tags ORDER BY ledger_id, name',
    ledgerId ? [ledgerId] : [],
  );
  return rows.map((r) => ({
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    name: String(r.name),
    color: r.color == null ? null : String(r.color),
  }));
}

/** Hard delete a tag; transaction_tags rows cascade away via the FK. */
export async function deleteTag(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM tags WHERE id = ?', [id]);
}

/** Map of transaction id → tag ids. */
export async function transactionTagMap(exec: Exec): Promise<Record<string, string[]>> {
  const rows = await exec('SELECT transaction_id, tag_id FROM transaction_tags');
  const m: Record<string, string[]> = {};
  for (const r of rows) {
    const txId = String(r.transaction_id);
    (m[txId] ??= []).push(String(r.tag_id));
  }
  return m;
}
