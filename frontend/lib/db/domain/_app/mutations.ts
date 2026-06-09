import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { setExchangeRate, deleteExchangeRate } from './system';
import { setMobileTabIds, setDisplayCurrency } from '../_shared/mobile-tabs';
import { mergeBackupConfig } from '../_shared/backup-config';
import { resetDb } from '../_shared/reset-tables';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  setExchangeRate: (exec, args: Args['setExchangeRate']) => {
    const date = str(args.date);
    const currency = str(args.currency).trim().toUpperCase();
    const rate = Number(args.rate);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new I18nError('error.fx.dateFormat', {}, 'Date must be YYYY-MM-DD');
    if (!currency) throw new I18nError('error.required.currency', {}, 'Currency is required');
    if (!(rate > 0)) throw new I18nError('error.fx.rateGt0', {}, 'Rate must be greater than 0');
    if (currency === 'USD') throw new I18nError('error.fx.usdHub', {}, 'USD is the hub currency and is not stored');
    return setExchangeRate(exec, {
      date,
      currency,
      rate,
      source: args.source ? str(args.source) : null,
    });
  },
  deleteExchangeRate: (exec, args: Args['deleteExchangeRate']) =>
    deleteExchangeRate(exec, str(args.date), str(args.currency).toUpperCase()),
  setMobileTabIds: (exec, args: Args['setMobileTabIds']) => {
    const ids = Array.isArray(args.ids) ? args.ids.filter((v): v is string => typeof v === 'string') : [];
    return setMobileTabIds(exec, ids);
  },
  setDisplayCurrency: (exec, args: Args['setDisplayCurrency']) =>
    setDisplayCurrency(exec, str(args.ledgerId), str(args.currency)),
  setBackupFrequency: async (exec, args: Args['setBackupFrequency']) => {
    const ms = Number(args.frequencyMs);
    const next = Number.isFinite(ms) ? Math.trunc(ms) : 60 * 60 * 1000;
    await mergeBackupConfig(exec, { frequencyMs: next });
  },
  setBackupRetention: async (exec, args: Args['setBackupRetention']) => {
    const n = Number(args.retention);
    const next = Number.isFinite(n) && n > 0 ? Math.trunc(n) : 14;
    await mergeBackupConfig(exec, { retention: next });
  },
  reset: (exec, _args: Args['reset']) => resetDb(exec),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
