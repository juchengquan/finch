import categoriesData from '@/data/categories.json';
import accountsData from '@/data/accounts.json';
import summaryData from '@/data/dashboard-summary.json';
import seedTxData from '@/data/transactions.json';
import type { Tx } from '@/lib/store';

// The mock JSON snapshots (category.spent, account.balance, monthSpent) already
// bake in the seed transactions. To let store mutations move the numbers without
// double-counting, we apply a delta: baseline + (currentStoreTotal − seedTotal).

const SEED = seedTxData as Tx[];

const expenseInCat = (txns: Tx[], catId: string) =>
  txns.reduce((s, t) => (t.category === catId && t.amount < 0 ? s + Math.abs(t.amount) : s), 0);

const sumForAccount = (txns: Tx[], acctId: string) =>
  txns.reduce((s, t) => (t.account === acctId ? s + t.amount : s), 0);

const totalExpense = (txns: Tx[]) =>
  txns.reduce((s, t) => (t.amount < 0 ? s + Math.abs(t.amount) : s), 0);

const totalIncome = (txns: Tx[]) =>
  txns.reduce((s, t) => (t.amount > 0 ? s + t.amount : s), 0);

export function categorySpent(txns: Tx[], catId: string) {
  const base = categoriesData.find((c) => c.id === catId)?.spent ?? 0;
  return base + (expenseInCat(txns, catId) - expenseInCat(SEED, catId));
}

export function accountBalance(txns: Tx[], acctId: string) {
  const base = accountsData.find((a) => a.id === acctId)?.balance ?? 0;
  return base + (sumForAccount(txns, acctId) - sumForAccount(SEED, acctId));
}

export function netWorth(txns: Tx[]) {
  return accountsData.reduce((s, a) => s + accountBalance(txns, a.id), 0);
}

export function monthSpent(txns: Tx[]) {
  return summaryData.monthSpent + (totalExpense(txns) - totalExpense(SEED));
}

export function monthIncome(txns: Tx[]) {
  return summaryData.monthIncome + (totalIncome(txns) - totalIncome(SEED));
}
