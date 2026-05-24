// Mock data for the expense tracker. Realistic personal finance shape.

const MOCK = {
  user: { name: 'Alex Morgan', currency: 'USD' },

  // Aggregate
  balance: 12847.32,
  monthSpent: 2438.16,
  monthBudget: 3200,
  monthIncome: 5800,
  monthChange: -8.4, // vs last month, %

  // Accounts
  accounts: [
    { id: 'chk', name: 'Chase Checking',     type: 'checking', group: 'cash',   balance: 4218.50,  last4: '4421', color: '#1f3a5f' },
    { id: 'sav', name: 'Marcus Savings',     type: 'savings',  group: 'cash',   balance: 8120.00,  last4: '7782', color: '#c89a3e' },
    { id: 'cc',  name: 'Amex Gold',          type: 'credit',   group: 'credit', balance: -842.18,  last4: '1009', color: '#3a2d1f' },
    { id: 'inv', name: 'Fidelity Brokerage', type: 'invest',   group: 'invest', balance: 21430.00, last4: '5530', color: '#2d4a3a' },
  ],

  // Account groups (for sectioned listing)
  accountGroups: [
    { id: 'cash',   name: 'Cash & Banking',   icon: 'wallet' },
    { id: 'credit', name: 'Credit Cards',     icon: 'tag' },
    { id: 'invest', name: 'Investments',      icon: 'arrow-u' },
    { id: 'loan',   name: 'Loans & Mortgage', icon: 'doc' },
  ],

  // Categories with month-to-date and budgets
  categories: [
    { id: 'food',   name: 'Food & Dining', spent: 612.40, budget: 700,  icon: 'fork',     hue: 12  },
    { id: 'rent',   name: 'Housing',       spent: 1850,   budget: 1850, icon: 'home',     hue: 220 },
    { id: 'trans',  name: 'Transport',     spent: 184.60, budget: 250,  icon: 'car',      hue: 200 },
    { id: 'shop',   name: 'Shopping',      spent: 312.18, budget: 300,  icon: 'bag',      hue: 280 },
    { id: 'enter',  name: 'Entertainment', spent:  98.40, budget: 200,  icon: 'film',     hue: 320 },
    { id: 'health', name: 'Health',        spent:  42.00, budget: 150,  icon: 'heart',    hue:  90 },
    { id: 'subs',   name: 'Subscriptions', spent: 138.58, budget: 150,  icon: 'sync',     hue: 160 },
    { id: 'misc',   name: 'Other',         spent:  50.00, budget: 100,  icon: 'dots',     hue:  40 },
  ],

  // Recent transactions (mixed accounts, ordered newest first)
  transactions: [
    { id: 't01', merchant: 'Blue Bottle Coffee',    category: 'food',  amount:  -6.75,  account: 'cc',  date: '2026-05-24', time: '08:14', note: 'Cortado',           pending: false },
    { id: 't02', merchant: 'Whole Foods Market',    category: 'food',  amount: -84.32,  account: 'cc',  date: '2026-05-23', time: '18:42', note: 'Weekly groceries',  pending: false },
    { id: 't03', merchant: 'Lyft',                  category: 'trans', amount: -18.40,  account: 'cc',  date: '2026-05-23', time: '14:01', note: 'To downtown',       pending: true  },
    { id: 't04', merchant: 'Spotify',               category: 'subs',  amount: -11.99,  account: 'cc',  date: '2026-05-22', time: '06:00', note: 'Premium · monthly', pending: false, recurring: true },
    { id: 't05', merchant: 'Acme Payroll',          category: null,    amount: 2900.00, account: 'chk', date: '2026-05-22', time: '00:00', note: 'Bi-weekly salary',  pending: false, kind: 'income' },
    { id: 't06', merchant: 'Trader Joe\u2019s',     category: 'food',  amount: -42.18,  account: 'cc',  date: '2026-05-21', time: '19:24', note: '',                  pending: false },
    { id: 't07', merchant: 'Apple',                 category: 'shop',  amount: -129.00, account: 'cc',  date: '2026-05-20', time: '12:08', note: 'AirPods cleaning',  pending: false },
    { id: 't08', merchant: 'NYC Transit',           category: 'trans', amount: -33.00,  account: 'cc',  date: '2026-05-20', time: '07:55', note: 'Weekly pass',       pending: false },
    { id: 't09', merchant: 'Pret a Manger',         category: 'food',  amount: -14.20,  account: 'cc',  date: '2026-05-19', time: '12:42', note: 'Lunch',             pending: false },
    { id: 't10', merchant: 'Netflix',               category: 'subs',  amount: -22.99,  account: 'cc',  date: '2026-05-19', time: '06:00', note: 'Standard · monthly',pending: false, recurring: true },
    { id: 't11', merchant: 'IKEA',                  category: 'shop',  amount: -183.18, account: 'cc',  date: '2026-05-18', time: '14:30', note: 'Office chair',      pending: false },
    { id: 't12', merchant: 'Equinox',               category: 'health',category: 'health', amount: -42.00, account: 'cc', date: '2026-05-17', time: '07:00', note: 'Day pass', pending: false },
    { id: 't13', merchant: 'Brooklyn Brewery',      category: 'enter', amount: -38.40,  account: 'cc',  date: '2026-05-16', time: '20:15', note: 'Friday drinks',     pending: false },
    { id: 't14', merchant: 'Rent · Greene St.',     category: 'rent',  amount: -1850.00,account: 'chk', date: '2026-05-15', time: '09:00', note: 'May rent',          pending: false, recurring: true },
    { id: 't15', merchant: 'Uber Eats',             category: 'food',  amount: -29.84,  account: 'cc',  date: '2026-05-14', time: '20:48', note: 'Thai · Sripraphai', pending: false },
    { id: 't16', merchant: 'Strand Books',          category: 'shop',  amount: -27.50,  account: 'cc',  date: '2026-05-13', time: '17:22', note: '',                  pending: false },
  ],

  // Subscriptions (recurring)
  subscriptions: [
    { id: 's1', name: 'Spotify',      amount: 11.99, cadence: 'monthly', next: 'Jun 22', logoHue: 145 },
    { id: 's2', name: 'Netflix',      amount: 22.99, cadence: 'monthly', next: 'Jun 19', logoHue:   0 },
    { id: 's3', name: 'NYT',          amount:  4.00, cadence: 'monthly', next: 'Jun 14', logoHue: 220 },
    { id: 's4', name: 'iCloud+',      amount:  9.99, cadence: 'monthly', next: 'Jun  8', logoHue: 200 },
    { id: 's5', name: 'Figma Pro',    amount: 15.00, cadence: 'monthly', next: 'Jun 28', logoHue: 280 },
    { id: 's6', name: 'Audible',      amount: 14.95, cadence: 'monthly', next: 'Jul  2', logoHue:  30 },
  ],

  // Upcoming bills
  bills: [
    { id: 'b1', name: 'Rent · Greene St.', amount: 1850, dueIn: 'in 22 days', dueDate: 'Jun 15' },
    { id: 'b2', name: 'ConEd Electric',    amount:   84, dueIn: 'in 6 days',  dueDate: 'May 30' },
    { id: 'b3', name: 'Verizon Fios',      amount:   69, dueIn: 'in 11 days', dueDate: 'Jun  4' },
    { id: 'b4', name: 'Amex Gold',         amount:  842, dueIn: 'in 14 days', dueDate: 'Jun  7' },
  ],

  // Savings goals
  goals: [
    { id: 'g1', name: 'Emergency Fund', target: 10000, saved: 6820, eta: 'Sep 2026',  hue: 200 },
    { id: 'g2', name: 'Japan trip',     target:  4500, saved: 2140, eta: 'Mar 2027',  hue:  12 },
    { id: 'g3', name: 'New laptop',     target:  2200, saved: 1850, eta: 'Aug 2026',  hue: 280 },
  ],

  // Daily spending for the last 30 days (for charts). Sum ≈ monthSpent.
  daily: [
    62,28,0,184,46,12,8,1922,18,4,32,86,140,42,18,6,210,28,12,38,148,84,42,29,38,18,6,98,84,8
  ],

  // Last 12 months total spend (for analytics)
  monthly: [
    {m:'Jun',v:2810},{m:'Jul',v:3120},{m:'Aug',v:2640},{m:'Sep',v:2980},
    {m:'Oct',v:3210},{m:'Nov',v:3890},{m:'Dec',v:4120},{m:'Jan',v:2730},
    {m:'Feb',v:2540},{m:'Mar',v:2920},{m:'Apr',v:2660},{m:'May',v:2438},
  ],

  // Cashflow (income vs spend per month)
  cashflow: [
    {m:'Jan', inc:5800, exp:2730},{m:'Feb', inc:5800, exp:2540},
    {m:'Mar', inc:5800, exp:2920},{m:'Apr', inc:5800, exp:2660},
    {m:'May', inc:5800, exp:2438},
  ],
};

// Category lookup helper
const catById = (id) => MOCK.categories.find((c) => c.id === id) || { name: 'Uncategorized', hue: 0 };
const acctById = (id) => MOCK.accounts.find((a) => a.id === id) || { name: '', last4: '' };

// Currency formatting (uses tweak-set currency)
const CURRENCIES = {
  USD: { sym: '$',    code: 'USD', locale: 'en-US' },
  EUR: { sym: '\u20AC', code: 'EUR', locale: 'de-DE' },
  GBP: { sym: '\u00A3', code: 'GBP', locale: 'en-GB' },
  JPY: { sym: '\u00A5', code: 'JPY', locale: 'ja-JP' },
};

// Convert USD-denominated mock values to other currencies at fixed rates so the
// numbers look right when the user toggles currency. Not real FX.
const FX = { USD: 1, EUR: 0.92, GBP: 0.79, JPY: 156.4 };

function fmtMoney(n, currency = 'USD', opts = {}) {
  const c = CURRENCIES[currency] || CURRENCIES.USD;
  const v = n * (FX[currency] || 1);
  const decimals = currency === 'JPY' ? 0 : (opts.compact ? 0 : 2);
  const abs = Math.abs(v).toLocaleString(c.locale, {
    minimumFractionDigits: opts.compact ? 0 : decimals,
    maximumFractionDigits: decimals,
  });
  return (v < 0 ? '-' : '') + c.sym + abs;
}

function fmtMoneyShort(n, currency = 'USD') {
  const c = CURRENCIES[currency] || CURRENCIES.USD;
  const v = Math.abs(n) * (FX[currency] || 1);
  if (v >= 1000) return c.sym + (v / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return c.sym + Math.round(v);
}

Object.assign(window, { MOCK, catById, acctById, fmtMoney, fmtMoneyShort, CURRENCIES, FX });
