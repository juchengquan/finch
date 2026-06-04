import { test, expect } from 'bun:test';
import { latestRateMap, convertViaRates } from '@/lib/fx';

const rates = [
  { date: '2026-05-13', currency: 'SGD', rate: 0.74570, source: 'ECB' },
  { date: '2026-05-24', currency: 'SGD', rate: 0.7460, source: 'ECB' }, // newest SGD
  { date: '2026-05-13', currency: 'JPY', rate: 0.00650, source: 'ECB' },
  { date: '2026-05-20', currency: 'JPY', rate: 0.00647, source: 'Yahoo' }, // newest JPY
];

test('latestRateMap picks the most recent date per currency + USD = 1', () => {
  const m = latestRateMap(rates);
  expect(m.get('SGD')).toBeCloseTo(0.7460, 4);
  expect(m.get('JPY')).toBeCloseTo(0.00647, 6);
  expect(m.get('USD')).toBe(1);
});

test('convertViaRates: same currency → identity', () => {
  const m = latestRateMap(rates);
  expect(convertViaRates(123.45, 'USD', 'USD', m)).toBe(123.45);
});

test('convertViaRates pivots through USD using latest rates', () => {
  const m = latestRateMap(rates);
  // 100 USD → SGD = 100 * 1 / 0.7460 ≈ 134.05
  expect(convertViaRates(100, 'USD', 'SGD', m)!).toBeCloseTo(100 / 0.7460, 4);
  // 1000 JPY → USD = 1000 * 0.00647 / 1 = 6.47
  expect(convertViaRates(1000, 'JPY', 'USD', m)!).toBeCloseTo(1000 * 0.00647, 4);
});

test('convertViaRates returns null when a currency is unknown', () => {
  const m = latestRateMap(rates);
  expect(convertViaRates(100, 'USD', 'XYZ', m)).toBeNull();
  expect(convertViaRates(100, 'ABC', 'SGD', m)).toBeNull();
});
