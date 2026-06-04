import accountsData from '@/data/accounts.json';
import accountGroupsData from '@/data/account-groups.json';
import categoriesData from '@/data/categories.json';
import ledgersData from '@/data/ledgers.json';
import transferGroupsData from '@/data/transfer-groups.json';
import counterpartiesData from '@/data/counterparties.json';
import exchangeRatesData from '@/data/exchange-rates.json';
import currenciesData from '@/data/currencies.json';

// Static reference data used as a pre-hydration fallback by a handful of
// screens. Everything else (monthly spending, cashflow, insights, MoM deltas)
// is derived from live transactions in lib/select.ts.
export const MOCK = {
  accounts: accountsData,
  accountGroups: accountGroupsData,
  categories: categoriesData,
};

export const LEDGER = {
  ledgers: ledgersData,
  transferGroups: transferGroupsData,
  counterparties: counterpartiesData,
  exchangeRates: exchangeRatesData,
};

export const CURRENCIES = currenciesData;

// Units per 1 USD — used by convertAmount as a pre-hydration fallback when the
// projected exchange_rates map isn't loaded yet. The live server-side rate
// lookups go through lib/db/queries/rates.
export const RATE: Record<string, number> = {
  USD: 1,
  EUR: 0.92,
  GBP: 0.79,
  JPY: 156.4,
  SGD: 1.35,
  CNY: 7.24,
};

export function convertAmount(amount: number, from: string, to: string) {
  if (from === to) return amount;
  const usd = amount / (RATE[from] ?? 1);
  return usd * (RATE[to] ?? 1);
}

export const catById = (id: string | null) => MOCK.categories.find((c) => c.id === id) || { name: 'Uncategorized', color: null };
export const acctById = (id: string) => MOCK.accounts.find((a) => a.id === id) || { name: '' };

// Formats an amount that is already denominated in `currency` (no FX
// conversion). Use for ledger data where amounts are stored natively.
export function fmtNative(amount: number, currency: string, opts: { signed?: boolean } = {}) {
  const c = CURRENCIES[currency as keyof typeof CURRENCIES] || CURRENCIES.USD;
  const decimals = currency === 'JPY' ? 0 : 2;
  const abs = Math.abs(amount).toLocaleString(c.locale, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
  const sign = amount < 0 ? '−' : opts.signed ? '+' : '';
  return sign + c.sym + abs;
}

export function fmtNativeShort(amount: number, currency: string) {
  const c = CURRENCIES[currency as keyof typeof CURRENCIES] || CURRENCIES.USD;
  const v = Math.abs(amount);
  if (v >= 1000) return c.sym + (v / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return c.sym + Math.round(v);
}
