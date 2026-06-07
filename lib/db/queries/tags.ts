// Tags: list, edit, delete. Create / assign in mutations.ts.

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

export interface TagPatch {
  name?: string;
  color?: string | null;
}

/** Update a tag's editable fields. */
export async function updateTag(exec: Exec, id: string, patch: TagPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  if (patch.name !== undefined) { sets.push('name = ?'); bind.push(patch.name); }
  if (patch.color !== undefined) { sets.push('color = ?'); bind.push(patch.color ?? null); }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE tags SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Hard delete a tag; transaction_tags rows cascade away via the FK. */
export async function deleteTag(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM tags WHERE id = ?', [id]);
}

