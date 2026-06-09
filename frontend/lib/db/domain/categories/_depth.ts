import type { Exec } from '../../core/repo';
import { I18nError } from '@/lib/i18n-error';

export async function categoryDepth(exec: Exec, id: string): Promise<number> {
  let cur: string | null = id;
  let depth = 0;
  for (let hop = 0; cur != null && hop < 10; hop++) {
    const rows = await exec('SELECT parent_id FROM categories WHERE id = ?', [cur]);
    if (!rows.length) throw new I18nError('error.notFound.category', {}, 'Category does not exist');
    depth++;
    cur = rows[0].parent_id == null ? null : String(rows[0].parent_id);
  }
  return depth;
}

export async function subtreeDepth(exec: Exec, id: string): Promise<number> {
  let frontier = [id];
  let depth = 1;
  for (let hop = 0; hop < 10; hop++) {
    if (!frontier.length) break;
    const placeholders = frontier.map(() => '?').join(',');
    const rows = await exec(
      `SELECT id FROM categories WHERE parent_id IN (${placeholders})`,
      frontier,
    );
    if (!rows.length) break;
    depth++;
    frontier = rows.map((r) => String(r.id));
  }
  return depth;
}

export async function isInSubtreeOf(
  exec: Exec,
  candidateId: string,
  ancestorId: string,
): Promise<boolean> {
  let cur: string | null = candidateId;
  for (let hop = 0; cur != null && hop < 10; hop++) {
    if (cur === ancestorId) return true;
    const rows = await exec('SELECT parent_id FROM categories WHERE id = ?', [cur]);
    if (!rows.length) return false;
    cur = rows[0].parent_id == null ? null : String(rows[0].parent_id);
  }
  return false;
}

export async function assertCanBeParent(exec: Exec, parentId: string): Promise<void> {
  const d = await categoryDepth(exec, parentId);
  if (d >= 3) throw new I18nError('error.category.depthCap', {}, 'Categories nest at most three levels deep');
}

export async function assertSubtreeFitsUnder(
  exec: Exec,
  movingId: string,
  newParentId: string,
): Promise<void> {
  const pd = await categoryDepth(exec, newParentId);
  const sd = await subtreeDepth(exec, movingId);
  if (pd + sd > 3) {
    throw new I18nError('error.category.depthCap', {}, 'Categories nest at most three levels deep');
  }
}
