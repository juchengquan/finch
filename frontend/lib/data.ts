import accountsData from '@/data/accounts.json';
import accountGroupsData from '@/data/account-groups.json';
import categoriesData from '@/data/categories.json';
import monthlySpendingData from '@/data/monthly-spending.json';
import cashflowData from '@/data/cashflow.json';
import ledgersData from '@/data/ledgers.json';
import transferGroupsData from '@/data/transfer-groups.json';
import counterpartiesData from '@/data/counterparties.json';
import recurringTemplatesData from '@/data/recurring-templates.json';
import exchangeRatesData from '@/data/exchange-rates.json';
import currenciesData from '@/data/currencies.json';
import insightsData from '@/data/insights.json';
import aprVsMayData from '@/data/apr-vs-may.json';
import scheduledItemsData from '@/data/scheduled-items.json';

// Static reference data used as a pre-hydration fallback by a handful of
// screens. Live data comes from the projected DB via the store. Series used by
// Insights (monthly, cashflow) are still baked here pending a derived-series
// rewrite — track in MASTER_PLAN.md §5.
export const MOCK = {
  accounts: accountsData,
  accountGroups: accountGroupsData,
  categories: categoriesData,
  monthly: monthlySpendingData,
  cashflow: cashflowData,
};

export const LEDGER = {
  ledgers: ledgersData,
  active: 'personal',
  transferGroups: transferGroupsData,
  counterparties: counterpartiesData,
  recurringTemplates: recurringTemplatesData,
  exchangeRates: exchangeRatesData,
  devices: [
    { id: 'iphone-15-pro', name: 'iPhone 15 Pro',  last: '2 min ago',  txn: 't01', current: 1 },
    { id: 'macbook-air',   name: 'MacBook Air',    last: '8 min ago',  txn: 't01', current: 0 },
    { id: 'ipad-pro-11',   name: 'iPad Pro 11"',   last: '1 hr ago',   txn: 't13', current: 0 },
    { id: 'web-firefox',   name: 'Web \u00b7 Firefox', last: 'yesterday', txn: 't22', current: 0 },
  ],
  categoryTree: [
    { parent: 'Food & Dining', hue: 12,  type: 'expense', children: ['Restaurants','Groceries','Coffee','Takeaway'] },
    { parent: 'Transport',     hue: 200, type: 'expense', children: ['Taxi & Rideshare','Public Transport','Fuel','Parking'] },
    { parent: 'Housing',       hue: 220, type: 'expense', children: ['Rent','Utilities','Internet','Maintenance'] },
    { parent: 'Shopping',      hue: 280, type: 'expense', children: ['Clothing','Electronics','Home','Books'] },
    { parent: 'Income',        hue:  90, type: 'income',  children: ['Salary','Freelance','Refunds','Interest'] },
  ],
  fxTx: {
    id: 't-jpy-001', merchant: 'Sushiro \u00b7 Tangs',
    date: '2026-05-13', time: '13:42',
    currency: 'JPY', amount: -3820,
    amountBase: -33.31, exchangeRate: 0.008721, rateDate: '2026-05-13',
    account: 'Wise JPY \u00b7 8841', ledger: 'Personal',
    category: 'Food & Dining > Restaurants', status: 'confirmed',
    note: 'Sushi lunch \u00b7 locked at import',
  },
};

export const CURRENCIES = currenciesData;

export const FX = { USD: 1, EUR: 0.92, GBP: 0.79, JPY: 156.4 };

// Units per 1 USD — used to convert between any two currencies for display.
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

export const INSIGHTS = insightsData as { tone: 'pos' | 'warn' | 'neut'; icon: string; title: string; body: string }[];
export const APR_VS_MAY = aprVsMayData as { name: string; a: number; b: number; d: number }[];
export const SCHEDULED_ITEMS = scheduledItemsData;

export const catById = (id: string | null) => MOCK.categories.find((c) => c.id === id) || { name: 'Uncategorized', hue: 0 };
export const acctById = (id: string) => MOCK.accounts.find((a) => a.id === id) || { name: '', last4: '' };

export function fmtMoney(n: number, currency: string = 'USD', opts: { compact?: boolean } = {}) {
  const c = CURRENCIES[currency as keyof typeof CURRENCIES] || CURRENCIES.USD;
  const v = n * (FX[currency as keyof typeof FX] || 1);
  const decimals = currency === 'JPY' ? 0 : (opts.compact ? 0 : 2);
  const abs = Math.abs(v).toLocaleString(c.locale, {
    minimumFractionDigits: opts.compact ? 0 : decimals,
    maximumFractionDigits: decimals,
  });
  return (v < 0 ? '-' : '') + c.sym + abs;
}

export function fmtMoneyShort(n: number, currency: string = 'USD') {
  const c = CURRENCIES[currency as keyof typeof CURRENCIES] || CURRENCIES.USD;
  const v = Math.abs(n) * (FX[currency as keyof typeof FX] || 1);
  if (v >= 1000) return c.sym + (v / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return c.sym + Math.round(v);
}

// Formats an amount that is already denominated in `currency` (no FX
// conversion). Use for ledger data where amounts are stored natively,
// unlike fmtMoney which converts a USD base amount into a display currency.
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