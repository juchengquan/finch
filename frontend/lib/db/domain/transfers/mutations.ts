import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { postTransfer } from '../../core/entries';
import {
  updateTransfer as qUpdateTransfer,
  deleteTransfer as qDeleteTransfer,
} from './queries';
import type { TransferPatch } from './types';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createTransfer: async (exec, args: Args['createTransfer']) => {
    const fromId = str(args.fromAccountId);
    const toId = str(args.toAccountId);
    const fromAmount = Math.abs(Number(args.fromAmount));
    const explicitToAmount = args.toAmount != null ? Math.abs(Number(args.toAmount)) : null;
    const date = str(args.date);
    const time = args.time ? str(args.time) : null;
    const note = args.note ? str(args.note) : null;
    const sourceTemplateId = args.sourceTemplateId ? str(args.sourceTemplateId) : null;
    const occurrenceDate = args.occurrenceDate ? str(args.occurrenceDate) : null;

    if (!fromAmount) throw new I18nError('error.transfer.amountGt0', {}, 'Transfer amount must be greater than 0');
    if (fromId === toId) throw new I18nError('error.transfer.sameAccount', {}, 'Pick two different accounts');

    const [from] = await exec('SELECT currency, name FROM accounts WHERE id = ?', [fromId]);
    const [to] = await exec('SELECT currency, name FROM accounts WHERE id = ?', [toId]);
    if (!from || !to) throw new I18nError('error.notFound.account', {}, 'Account not found');

    const fromCurrency = String(from.currency);
    const toCurrency = String(to.currency);
    if (explicitToAmount != null) {
      if (!(explicitToAmount > 0)) throw new I18nError('error.transfer.receivedGt0', {}, 'Received amount must be greater than 0');
      if (fromCurrency === toCurrency && Math.abs(explicitToAmount - fromAmount) > 0.005) {
        throw new I18nError('error.transfer.sameCurrencyMismatch', {}, 'Same-currency transfer amounts must match');
      }
    }

    await postTransfer(exec, {
      fromAccountId: fromId,
      toAccountId: toId,
      fromAmount,
      toAmount: explicitToAmount,
      date,
      time,
      note,
      sourceTemplateId,
      occurrenceDate,
    });
  },
  updateTransfer: (exec, args: Args['updateTransfer']) =>
    qUpdateTransfer(exec, str(args.id), (args.patch ?? {}) as TransferPatch),
  deleteTransfer: (exec, args: Args['deleteTransfer']) =>
    qDeleteTransfer(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
