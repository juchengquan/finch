import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { isAccountType } from '@/lib/account-types';
import { newId } from '../_shared/ids';
import {
  createAccount as qCreateAccount,
  updateAccount as qUpdateAccount,
  archiveAccount as qArchiveAccount,
  unarchiveAccount as qUnarchiveAccount,
  deleteAccount as qDeleteAccount,
  type AccountPatch,
} from './queries';
import {
  createAccountGroup as qCreateAccountGroup,
  updateAccountGroup as qUpdateAccountGroup,
  deleteAccountGroup as qDeleteAccountGroup,
  type AccountGroupPatch,
} from '../accountGroups/queries';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createAccount: async (exec, args: Args['createAccount']) => {
    const ledgerId = str(args.ledgerId || 'personal');
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.accountName', {}, 'Account name is required');
    const type = str(args.type || 'savings');
    if (!isAccountType(type)) throw new I18nError('error.account.unknownType', { type }, `Unknown account type "${type}"`);
    await qCreateAccount(exec, {
      id: str(args.id || newId('acct')),
      ledgerId,
      name,
      type,
      currency: str(args.currency || 'SGD'),
      groupId: args.groupId ? str(args.groupId) : null,
      openingBalance: Number(args.openingBalance ?? 0),
      color: args.color ? str(args.color) : null,
    });
  },
  updateAccount: async (exec, args: Args['updateAccount']) => {
    const patch = (args.patch ?? {}) as AccountPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.accountName', {}, 'Account name is required');
    if (patch.type !== undefined && !isAccountType(str(patch.type))) {
      throw new I18nError('error.account.unknownType', { type: String(patch.type) }, `Unknown account type "${patch.type}"`);
    }
    await qUpdateAccount(exec, str(args.id), patch);
  },
  archiveAccount: (exec, args: Args['archiveAccount']) =>
    qArchiveAccount(exec, str(args.id)),
  unarchiveAccount: (exec, args: Args['unarchiveAccount']) =>
    qUnarchiveAccount(exec, str(args.id)),
  deleteAccount: (exec, args: Args['deleteAccount']) =>
    qDeleteAccount(exec, str(args.id)),
  createAccountGroup: async (exec, args: Args['createAccountGroup']) => {
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.groupName', {}, 'Group name is required');
    await qCreateAccountGroup(exec, {
      id: str(args.id || newId('ag')),
      ledgerId: str(args.ledgerId || 'personal'),
      name,
    });
  },
  updateAccountGroup: async (exec, args: Args['updateAccountGroup']) => {
    const patch = (args.patch ?? {}) as AccountGroupPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) throw new I18nError('error.required.groupName', {}, 'Group name is required');
    await qUpdateAccountGroup(exec, str(args.id), patch);
  },
  deleteAccountGroup: (exec, args: Args['deleteAccountGroup']) =>
    qDeleteAccountGroup(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
