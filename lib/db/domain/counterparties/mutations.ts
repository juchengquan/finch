import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import {
  createCounterparty as qCreateCounterparty,
  updateCounterparty as qUpdateCounterparty,
  deleteCounterparty as qDeleteCounterparty,
  verifyCounterparty as qVerifyCounterparty,
  unverifyCounterparty as qUnverifyCounterparty,
} from './queries';
import type { CounterpartyPatch } from './types';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createCounterparty: (exec, args: Args['createCounterparty']) => {
    const name = str(args.name).trim();
    if (!name) throw new I18nError('error.required.merchantName', {}, 'Merchant name is required');
    return qCreateCounterparty(exec, {
      id: str(args.id || newId('cp')),
      ledgerId: str(args.ledgerId || 'personal'),
      name,
    });
  },
  updateCounterparty: (exec, args: Args['updateCounterparty']) => {
    const patch = (args.patch ?? {}) as CounterpartyPatch;
    if (patch.name !== undefined && !str(patch.name).trim()) {
      throw new I18nError('error.required.merchantName', {}, 'Merchant name is required');
    }
    return qUpdateCounterparty(exec, str(args.id), patch);
  },
  deleteCounterparty: (exec, args: Args['deleteCounterparty']) =>
    qDeleteCounterparty(exec, str(args.id)),
  verifyCounterparty: (exec, args: Args['verifyCounterparty']) =>
    qVerifyCounterparty(exec, str(args.id)),
  unverifyCounterparty: (exec, args: Args['unverifyCounterparty']) =>
    qUnverifyCounterparty(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
