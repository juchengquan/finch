import { test, expect, beforeEach } from 'bun:test';
import { lsRead, lsWrite } from '@/lib/persistence';
import type { PersistState } from '@/lib/db/repo';

// Minimal localStorage stand-in for the Node/bun test environment.
const store = new Map<string, string>();
(globalThis as { localStorage?: Storage }).localStorage = {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => void store.set(k, v),
  removeItem: (k: string) => void store.delete(k),
  clear: () => store.clear(),
  key: () => null,
  length: 0,
} as Storage;

const sample: PersistState = {
  transactions: [{ id: 't01', merchant: 'Blue Bottle', category: 'food', amount: -6.75, account: 'cc', date: '2026-05-24', pending: false }],
  pending: [],
  budgetOverrides: { food: 800 },
  accountOverrides: {},
  verifiedExtra: [],
  aliasExtra: {},
  recurring: [],
};

beforeEach(() => store.clear());

test('lsRead returns null when nothing is stored', () => {
  expect(lsRead()).toBeNull();
});

test('lsWrite → lsRead round-trips bare PersistState', () => {
  lsWrite(sample);
  const out = lsRead();
  expect(out?.transactions[0].amount).toBe(-6.75);
  expect(out?.budgetOverrides.food).toBe(800);
});

test('lsRead tolerates the legacy zustand { state, version } wrapper', () => {
  store.set('finch-store', JSON.stringify({ state: sample, version: 1 }));
  const out = lsRead();
  expect(out?.transactions[0].merchant).toBe('Blue Bottle');
});

test('lsRead fills missing fields with defaults', () => {
  store.set('finch-store', JSON.stringify({ transactions: [] }));
  const out = lsRead();
  expect(out).toEqual({
    transactions: [],
    pending: [],
    recurring: [],
    budgetOverrides: {},
    accountOverrides: {},
    verifiedExtra: [],
    aliasExtra: {},
  });
});

test('lsRead returns null for corrupt or shapeless data', () => {
  store.set('finch-store', 'not json');
  expect(lsRead()).toBeNull();
  store.set('finch-store', JSON.stringify({ foo: 'bar' }));
  expect(lsRead()).toBeNull();
});
