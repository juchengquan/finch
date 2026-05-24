// Ledger-schema mock data. Bolts onto MOCK without touching the existing
// app data. These shapes mirror the SQLite schema in the design doc:
// ledgers · transfer_groups · counterparties · recurring_templates ·
// recurring_splits · exchange_rates · sync_log · pending review.

const LEDGER = {
  // Top-level "books". A user can switch between ledgers; every entity
  // below is scoped to one.
  ledgers: [
    { id: 'personal', name: 'Personal',       base: 'SGD', isDefault: 1, accounts: 4, txns: 1842, color: '#c96442',
      tagline: 'Daily life · the main book' },
    { id: 'family',   name: 'Family',         base: 'SGD', isDefault: 0, accounts: 2, txns:  612, color: '#3d6b46',
      tagline: 'Joint expenses with Sam' },
    { id: 'business', name: 'Side studio',    base: 'CNY', isDefault: 0, accounts: 3, txns:  284, color: '#5d76a8',
      tagline: 'Freelance income & expenses' },
    { id: 'travel',   name: 'Japan ’26',      base: 'JPY', isDefault: 0, accounts: 2, txns:   38, color: '#c89a3e',
      tagline: 'Closed trip · archived next month' },
  ],

  // Currently active ledger (display value).
  active: 'personal',

  // Transfer groups — every cross-account or cross-ledger movement
  // produces one row here, plus exactly two transactions sharing the id.
  transferGroups: [
    { id: 'tg-001', date: '2026-05-22', amountBase: 1500.00,
      fromCurrency: 'SGD', toCurrency: 'SGD', exchangeRate: 1.0000,
      fromAccount: 'UOB One',  fromLedger: 'Personal',
      toAccount:   'Marcus Savings', toLedger: 'Personal',
      notes: 'Monthly savings sweep' },
    { id: 'tg-002', date: '2026-05-18', amountBase: 80000.00,
      fromCurrency: 'SGD', toCurrency: 'CNY', exchangeRate: 5.2841,
      amountFrom: 80000.00, amountTo: 422728.00,
      fromAccount: 'UOB One',  fromLedger: 'Personal',
      toAccount:   'CMB · 6291', toLedger: 'Side studio',
      notes: 'Quarterly capital transfer · locked at 5.2841' },
    { id: 'tg-003', date: '2026-05-12', amountBase: 540.00,
      fromCurrency: 'SGD', toCurrency: 'JPY', exchangeRate: 117.43,
      amountFrom: 540.00, amountTo: 63412.00,
      fromAccount: 'Amex Gold',  fromLedger: 'Personal',
      toAccount:   'Wise JPY · 8841', toLedger: 'Japan ’26',
      notes: 'Trip top-up · rate locked' },
  ],

  // Counterparties — merchants with alias arrays. Maps to schema 6.7.
  counterparties: [
    { id: 'cp-01', name: '7-Eleven',          aliases: ['7-11','7Eleven','SEVEN ELEVEN'], category: 'Food',    verified: 1, txCount:  42, hue:  12 },
    { id: 'cp-02', name: 'Grab',              aliases: ['GRAB SG','GRAB*RIDE','GRABFOOD'], category: 'Transport',verified: 1, txCount:  31, hue: 200 },
    { id: 'cp-03', name: 'NTUC FairPrice',    aliases: ['NTUC','FAIRPRICE','NTUC SHEN'],   category: 'Food',    verified: 1, txCount:  28, hue:  12 },
    { id: 'cp-04', name: 'Don Don Donki',     aliases: ['DON DONKI','DDD JURONG'],         category: 'Food',    verified: 0, txCount:   6, hue:   8 },
    { id: 'cp-05', name: 'Apple',             aliases: ['APPLE.COM','APPLE STORE SG'],     category: 'Shopping',verified: 1, txCount:   4, hue: 280 },
    { id: 'cp-06', name: 'Sushiro',           aliases: ['SUSHIRO TANGS','すしろー'],         category: 'Food',    verified: 0, txCount:   3, hue:  12 },
  ],

  // Pending review queue — transactions awaiting confirmation. These come
  // from (a) recurring templates with auto_post=0 and (b) imports that
  // couldn't match a counterparty.
  pending: [
    { id: 'pen-1', merchant: 'Salary · Acme',     amount:  5800.00, currency: 'SGD', date: '2026-05-25', account: 'UOB One', reason: 'Recurring · waiting for confirmation', source: 'rt-salary' },
    { id: 'pen-2', merchant: 'Don Don Donki',     amount:  -82.40,  currency: 'SGD', date: '2026-05-24', account: 'Amex Gold', reason: 'New merchant · please verify name', source: 'import' },
    { id: 'pen-3', merchant: 'Sushiro · Tangs',   amount:  -34.20,  currency: 'SGD', date: '2026-05-24', account: 'Amex Gold', reason: 'New merchant · matched “すしろー”', source: 'import' },
    { id: 'pen-4', merchant: 'JR East · IC top-up', amount: -3000,  currency: 'JPY', date: '2026-05-23', account: 'Wise JPY', reason: 'No FX rate cached for this date', source: 'import' },
  ],

  // Recurring templates — schema 6.12. The salary template uses splits.
  recurringTemplates: [
    { id: 'rt-salary',  name: 'Acme · salary',          type: 'income',  amount: 5800,  frequency: 'monthly', dayOfMonth: 25, account: 'UOB One',
      autoPost: 0, splits: [
        { account: 'UOB One',        pct: 60, abs: null, label: 'Daily spending' },
        { account: 'Marcus Savings', pct: 25, abs: null, label: 'Savings sweep' },
        { account: 'Fidelity',       pct: 15, abs: null, label: 'Auto-invest' },
      ], nextRun: 'May 25', lastRun: 'Apr 25' },
    { id: 'rt-rent',    name: 'Rent · Greene St.',       type: 'expense', amount: 1850, frequency: 'monthly', dayOfMonth: 1,  account: 'UOB One',  autoPost: 1, nextRun: 'Jun 1',  lastRun: 'May 1'  },
    { id: 'rt-sweep',   name: 'Savings sweep',           type: 'transfer',amount: 800,  frequency: 'monthly', dayOfMonth: 28, account: 'Marcus Savings', from: 'UOB One', autoPost: 1, nextRun: 'May 28', lastRun: 'Apr 28' },
    { id: 'rt-coned',   name: 'ConEd Electric',          type: 'expense', amount: null, varies: 1, frequency: 'monthly', dayOfMonth: 30, account: 'UOB One', autoPost: 0, nextRun: 'May 30', lastRun: 'Apr 30' },
    { id: 'rt-spotify', name: 'Spotify Premium',         type: 'expense', amount: 11.99,frequency: 'monthly', dayOfMonth: 22, account: 'Amex Gold', autoPost: 1, nextRun: 'Jun 22', lastRun: 'May 22' },
    { id: 'rt-icloud',  name: 'iCloud+ Family',          type: 'expense', amount: 9.99, frequency: 'monthly', dayOfMonth:  8, account: 'Amex Gold', autoPost: 1, nextRun: 'Jun 8',  lastRun: 'May 8'  },
  ],

  // Daily exchange rates (truncated). Two currencies for the demo. Used
  // to populate the rate-history page.
  exchangeRates: [
    { date: '2026/05/24', currency: 'JPY', rate: 0.00872, source: 'ECB' },
    { date: '2026/05/24', currency: 'CNY', rate: 0.18950, source: 'ECB' },
    { date: '2026/05/24', currency: 'USD', rate: 1.34120, source: 'ECB' },
    { date: '2026/05/24', currency: 'EUR', rate: 1.45920, source: 'ECB' },
    { date: '2026/05/23', currency: 'JPY', rate: 0.00869, source: 'ECB' },
    { date: '2026/05/23', currency: 'CNY', rate: 0.18920, source: 'ECB' },
    { date: '2026/05/22', currency: 'JPY', rate: 0.00871, source: 'ECB' },
    { date: '2026/05/22', currency: 'CNY', rate: 0.18931, source: 'ECB' },
    { date: '2026/05/21', currency: 'JPY', rate: 0.00873, source: 'ECB' },
    { date: '2026/05/21', currency: 'CNY', rate: 0.18928, source: 'ECB' },
    { date: '2026/05/20', currency: 'JPY', rate: 0.00868, source: 'Yahoo' },
    { date: '2026/05/20', currency: 'CNY', rate: 0.18915, source: 'Yahoo' },
    { date: '2026/05/19', currency: 'JPY', rate: 0.00874, source: 'ECB' },
    { date: '2026/05/19', currency: 'CNY', rate: 0.18935, source: 'ECB' },
    { date: '2026/05/18', currency: 'JPY', rate: 0.00876, source: 'ECB' },
    { date: '2026/05/18', currency: 'CNY', rate: 0.18927, source: 'manual' },
  ],

  // Sync log — schema 6.17. One row per device.
  devices: [
    { id: 'iphone-15-pro',     name: 'iPhone 15 Pro',     last: '2 min ago',  txn: 't01', current: 1 },
    { id: 'macbook-air',       name: 'MacBook Air',       last: '8 min ago',  txn: 't01', current: 0 },
    { id: 'ipad-pro-11',       name: 'iPad Pro 11"',      last: '1 hr ago',   txn: 't13', current: 0 },
    { id: 'web-firefox',       name: 'Web · Firefox',     last: 'yesterday',  txn: 't22', current: 0 },
  ],

  // Hierarchical categories — schema 6.4. Parent + children pattern.
  categoryTree: [
    { parent: 'Food & Dining', hue: 12,  type: 'expense', children: ['Restaurants','Groceries','Coffee','Takeaway'] },
    { parent: 'Transport',     hue: 200, type: 'expense', children: ['Taxi & Rideshare','Public Transport','Fuel','Parking'] },
    { parent: 'Housing',       hue: 220, type: 'expense', children: ['Rent','Utilities','Internet','Maintenance'] },
    { parent: 'Shopping',      hue: 280, type: 'expense', children: ['Clothing','Electronics','Home','Books'] },
    { parent: 'Income',        hue:  90, type: 'income',  children: ['Salary','Freelance','Refunds','Interest'] },
  ],

  // A multi-currency transaction example, used by the txn-detail screen.
  fxTx: {
    id: 't-jpy-001', merchant: 'Sushiro · Tangs',
    date: '2026-05-13', time: '13:42',
    currency: 'JPY', amount: -3820,
    amountBase: -33.31, exchangeRate: 0.008721, rateDate: '2026-05-13',
    account: 'Wise JPY · 8841', ledger: 'Personal',
    category: 'Food & Dining > Restaurants', status: 'confirmed',
    note: 'Sushi lunch — locked at import',
  },
};

Object.assign(window, { LEDGER });
