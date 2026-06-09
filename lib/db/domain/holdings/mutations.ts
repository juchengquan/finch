import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import {
  createHolding as qCreateHolding,
  updateHolding as qUpdateHolding,
  setHoldingPrice as qSetHoldingPrice,
  deleteHolding as qDeleteHolding,
} from './queries';
import type { HoldingPatch } from './types';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createHolding: async (exec, args: Args['createHolding']) => {
    const accountId = str(args.accountId).trim();
    const symbol = str(args.symbol).trim().toUpperCase();
    const shares = Number(args.shares);
    const costBasis = Number(args.costBasis);
    if (!accountId) throw new I18nError('error.required.investmentAccount', {}, 'An investment account is required');
    if (!symbol) throw new I18nError('error.required.symbol', {}, 'Symbol is required');
    if (!(shares > 0)) throw new I18nError('error.holding.sharesGt0', {}, 'Shares must be greater than 0');
    if (!(costBasis >= 0)) throw new I18nError('error.holding.costBasisGte0', {}, 'Cost basis must be 0 or greater');
    const [acct] = await exec('SELECT type, currency, ledger_id FROM accounts WHERE id = ?', [accountId]);
    if (!acct) throw new I18nError('error.notFound.account', {}, 'Account not found');
    if (String(acct.type) !== 'investment') throw new I18nError('error.holding.notInvestment', {}, 'Holdings can only be added to an investment account');
    const ledgerId = str(args.ledgerId || acct.ledger_id || 'personal');
    const accountCurrency = String(acct.currency ?? 'USD');
    const requested = args.currency ? str(args.currency).trim().toUpperCase() : accountCurrency;
    if (requested !== accountCurrency) {
      throw new I18nError('error.holding.currencyMismatch', { currency: accountCurrency }, `Holding currency must match the account currency (${accountCurrency})`);
    }
    const currency = accountCurrency;
    await qCreateHolding(exec, {
      id: str(args.id || newId('h')),
      ledgerId,
      accountId,
      symbol,
      name: args.name ? str(args.name).trim() : null,
      shares,
      costBasis,
      currency,
      lastPrice: args.lastPrice == null ? null : Number(args.lastPrice),
      lastPriceDate: args.lastPriceDate ? str(args.lastPriceDate) : null,
      notes: args.notes ? str(args.notes) : null,
    });
  },
  updateHolding: (exec, args: Args['updateHolding']) => {
    const id = str(args.id);
    const patch = (args.patch ?? {}) as Record<string, unknown>;
    const normalized: HoldingPatch = {};
    if (patch.symbol !== undefined) {
      const sym = str(patch.symbol).trim().toUpperCase();
      if (!sym) throw new I18nError('error.holding.symbolEmpty', {}, 'Symbol cannot be empty');
      normalized.symbol = sym;
    }
    if (patch.name !== undefined) normalized.name = patch.name == null ? null : str(patch.name);
    if (patch.shares !== undefined) {
      const s = Number(patch.shares);
      if (!(s > 0)) throw new I18nError('error.holding.sharesGt0', {}, 'Shares must be greater than 0');
      normalized.shares = s;
    }
    if (patch.costBasis !== undefined) {
      const c = Number(patch.costBasis);
      if (!(c >= 0)) throw new I18nError('error.holding.costBasisGte0', {}, 'Cost basis must be 0 or greater');
      normalized.costBasis = c;
    }
    if (patch.notes !== undefined) normalized.notes = patch.notes == null ? null : str(patch.notes);
    return qUpdateHolding(exec, id, normalized);
  },
  setHoldingPrice: (exec, args: Args['setHoldingPrice']) => {
    const id = str(args.id);
    const price = args.price == null ? null : Number(args.price);
    const date = price == null ? null : args.date == null ? null : str(args.date);
    if (price !== null && !(price >= 0)) throw new I18nError('error.holding.priceGte0', {}, 'Price must be 0 or greater');
    if (date !== null && !/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new I18nError('error.fx.dateFormat', {}, 'Date must be YYYY-MM-DD');
    return qSetHoldingPrice(exec, id, price, date);
  },
  deleteHolding: (exec, args: Args['deleteHolding']) =>
    qDeleteHolding(exec, str(args.id)),
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
