import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import {
  updateCategory as qUpdateCategory,
  deleteCategory as qDeleteCategory,
  type CategoryPatch,
} from './queries';
import { assertCanBeParent, assertSubtreeFitsUnder, isInSubtreeOf } from './_depth';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createCategory: async (exec, args: Args['createCategory']) => {
    const ledgerId = str(args.ledgerId || 'personal');
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.categoryName', {}, 'Category name is required');
    const type = args.type ? str(args.type) : 'expense';
    const icon = args.icon ? str(args.icon) : null;
    const color = args.color ? str(args.color) : null;
    const parentId = args.parentId ? str(args.parentId) : null;
    if (parentId != null) await assertCanBeParent(exec, parentId);
    const rows = await exec('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM categories WHERE ledger_id = ?', [ledgerId]);
    await exec("INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,datetime('now'),datetime('now'))", [
      newId('cat'), ledgerId, parentId, name, type, icon, color, Number(rows[0]?.n ?? 0),
    ]);
    return;
  },
  updateCategory: async (exec, args: Args['updateCategory']) => {
    const id = str(args.id);
    const patch = (args.patch ?? {}) as CategoryPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.categoryName', {}, 'Category name is required');
    if (patch.parentId !== undefined && patch.parentId !== null) {
      if (patch.parentId === id) throw new I18nError('error.category.selfParent', {}, 'A category cannot be its own parent');
      if (await isInSubtreeOf(exec, patch.parentId, id)) {
        throw new I18nError('error.category.underDescendant', {}, 'A category cannot be moved under its own descendant');
      }
      await assertSubtreeFitsUnder(exec, id, patch.parentId);
    }
    await qUpdateCategory(exec, id, patch);
    return;
  },
  deleteCategory: (exec, args: Args['deleteCategory']) =>
    qDeleteCategory(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
