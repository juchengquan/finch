import { test, expect } from 'bun:test';
import { fmtNative, fmtNativeShort, convertAmount } from '@/lib/data';
import { makeLookups } from '@/components/use-lookups';

test('fmtNative formats a negative SGD amount with the SGD symbol', () => {
  expect(fmtNative(-84.32, 'SGD')).toBe('−S$84.32');
});

test('fmtNative adds a + for signed positive amounts', () => {
  expect(fmtNative(100, 'USD', { signed: true })).toBe('+$100.00');
});

test('fmtNative renders JPY with no decimals', () => {
  expect(fmtNative(3000, 'JPY')).toBe('¥3,000');
});

test('fmtNativeShort abbreviates thousands', () => {
  expect(fmtNativeShort(1234, 'USD')).toBe('$1.2k');
  expect(fmtNativeShort(500, 'USD')).toBe('$500');
});

test('convertAmount converts via the USD pivot', () => {
  expect(convertAmount(135, 'SGD', 'USD')).toBeCloseTo(100, 5);
  expect(convertAmount(100, 'USD', 'USD')).toBe(100);
});

test('lookups fall back to the seed only before the store has loaded', () => {
  const { catById, acctById } = makeLookups([], []);
  expect(catById('food').name).toBe('Food & Dining');
  expect(catById(null).name).toBe('Uncategorized');
  expect(acctById('cc').name).toBe('Amex Gold');
});

test('lookups resolve the user\'s own categories and accounts once the store has them', () => {
  const { catById, acctById } = makeLookups(
    [{ id: 'cat-mine', name: 'Climbing', color: '#123456' }],
    [{ id: 'acc-mine', name: 'Credit union', color: null }],
  );
  // Used to read the seed: a created category showed "Uncategorized", a new account no name.
  expect(catById('cat-mine')).toEqual({ name: 'Climbing', color: '#123456' });
  expect(acctById('acc-mine').name).toBe('Credit union');
  // And the seed no longer leaks in once the store is loaded.
  expect(catById('food').name).toBe('Uncategorized');
});
