import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import {
  updateTag as qUpdateTag,
  deleteTag as qDeleteTag,
} from './queries';
import type { TagPatch } from './types';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createTag: async (exec, args: Args['createTag']) => {
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.tagName', {}, 'Tag name is required');
    await exec(
      "INSERT INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES (?,?,?,?,datetime('now'),datetime('now'))",
      [
        args.id ? str(args.id) : newId('tag'),
        str(args.ledgerId || 'personal'),
        name,
        args.color ? str(args.color) : null,
      ],
    );
  },
  updateTag: (exec, args: Args['updateTag']) => {
    const patch = (args.patch ?? {}) as TagPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) {
      throw new I18nError('error.required.tagName', {}, 'Tag name is required');
    }
    return qUpdateTag(exec, str(args.id), patch);
  },
  deleteTag: (exec, args: Args['deleteTag']) =>
    qDeleteTag(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
