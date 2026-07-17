import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import {
  createAccountGroup as qCreateAccountGroup,
  updateAccountGroup as qUpdateAccountGroup,
  deleteAccountGroup as qDeleteAccountGroup,
} from './queries';
import type { AccountGroupPatch } from './types';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createAccountGroup: (exec, args: Args['createAccountGroup']) => {
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.groupName', {}, 'Group name is required');
    return qCreateAccountGroup(exec, {
      id: str(args.id || newId('ag')),
      ledgerId: str(args.ledgerId || 'personal'),
      name,
      color: args.color ?? null,
    });
  },
  updateAccountGroup: (exec, args: Args['updateAccountGroup']) => {
    const patch = (args.patch ?? {}) as AccountGroupPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) {
      throw new I18nError('error.required.groupName', {}, 'Group name is required');
    }
    return qUpdateAccountGroup(exec, str(args.id), patch);
  },
  deleteAccountGroup: (exec, args: Args['deleteAccountGroup']) =>
    qDeleteAccountGroup(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
