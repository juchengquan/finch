// Canonical account types live in the DB (the `accounts.type` CHECK constraint).
// The original mock used looser display names ('checking', 'invest'); the domain
// model merges checking into savings, so the editable set is the canonical one.

export const ACCOUNT_TYPE_VALUES = ['savings', 'credit_card', 'investment', 'cash', 'fx', 'virtual'] as const;
export type AccountType = (typeof ACCOUNT_TYPE_VALUES)[number];

// Options offered in the account create/edit form (the common, user-pickable set).
export const ACCOUNT_TYPE_OPTIONS: { value: AccountType; label: string }[] = [
  { value: 'savings', label: 'Savings' },
  { value: 'credit_card', label: 'Credit' },
  { value: 'investment', label: 'Investment' },
  { value: 'cash', label: 'Cash' },
];

const LABELS: Record<string, string> = {
  savings: 'Savings',
  credit_card: 'Credit',
  investment: 'Investment',
  cash: 'Cash',
  fx: 'FX',
  virtual: 'Virtual',
};

export const accountTypeLabel = (t: string): string => LABELS[t] ?? t;
export const isAccountType = (t: string): t is AccountType =>
  (ACCOUNT_TYPE_VALUES as readonly string[]).includes(t);

/**
 * Whether an account of this type counts toward net worth by default at
 * create-time. Credit cards are liabilities and excluded by default; every
 * other type is an asset and included. Users can still flip the flag per
 * account afterwards.
 */
export const defaultIncludeInNetWorth = (t: string): 0 | 1 =>
  t === 'credit_card' ? 0 : 1;

// Legacy display names ('checking'/'invest') → canonical, for mock fallbacks.
const DISPLAY_TO_DB: Record<string, AccountType> = {
  checking: 'savings',
  savings: 'savings',
  credit: 'credit_card',
  invest: 'investment',
  cash: 'cash',
  fx: 'fx',
  virtual: 'virtual',
};
export const toDbType = (t: string): AccountType =>
  DISPLAY_TO_DB[t] ?? (isAccountType(t) ? t : 'savings');
