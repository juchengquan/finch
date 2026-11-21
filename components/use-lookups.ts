'use client';

import { useMemo } from 'react';
import { useFinanceStore } from '@/lib/store';
import { MOCK } from '@/lib/data';

export interface NamedRef {
  name: string;
  color: string | null;
}

const UNCATEGORIZED: NamedRef = { name: 'Uncategorized', color: null };
const NO_ACCOUNT: NamedRef = { name: '', color: null };

/** Id → name/colour lookups over the user's own categories and accounts. The
 *  old `catById`/`acctById` read the demo seed, so a category the user created
 *  showed as "Uncategorized" and a new account showed no name. The seed now only
 *  stands in before the store has loaded (when the store still holds the seed's
 *  transactions too). */
export function makeLookups(
  categories: readonly { id: string; name: string; color?: string | null }[],
  accounts: readonly { id: string; name: string; color?: string | null }[],
) {
  const cats = categories.length ? categories : (MOCK.categories as { id: string; name: string; color?: string | null }[]);
  const accts = accounts.length ? accounts : (MOCK.accounts as { id: string; name: string; color?: string | null }[]);
  const catMap = new Map(cats.map((c) => [c.id, { name: c.name, color: c.color ?? null }]));
  const acctMap = new Map(accts.map((a) => [a.id, { name: a.name, color: a.color ?? null }]));
  return {
    catById: (id: string | null | undefined): NamedRef => (id != null && catMap.get(id)) || UNCATEGORIZED,
    acctById: (id: string | null | undefined): NamedRef => (id != null && acctMap.get(id)) || NO_ACCOUNT,
  };
}

export function useLookups() {
  const categories = useFinanceStore((s) => s.categories);
  const accounts = useFinanceStore((s) => s.accounts);
  return useMemo(() => makeLookups(categories, accounts), [categories, accounts]);
}
