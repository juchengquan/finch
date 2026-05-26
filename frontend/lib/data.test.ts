import { test, expect } from 'bun:test';
import { fmtNative, fmtNativeShort, convertAmount, catById, acctById } from '@/lib/data';

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

test('catById resolves ids and falls back to Uncategorized', () => {
  expect(catById('food').name).toBe('Food & Dining');
  expect(catById(null).name).toBe('Uncategorized');
});

test('acctById resolves an account id', () => {
  expect(acctById('cc').name).toBe('Amex Gold');
});
