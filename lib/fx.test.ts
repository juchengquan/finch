import { test, expect } from 'bun:test';
import { latestRateMap, convertViaRates } from '@/lib/fx';

const rates = [
  { date: '2026-05-13', currency: 'USD', rate: 1.34, source: 'ECB' },
  { date: '2026-05-24', currency: 'USD', rate: 1.341, source: 'ECB' }, // newest USD
  { date: '2026-05-13', currency: 'JPY', rate: 0.00872, source: 'ECB' },
  { date: '2026-05-20', currency: 'JPY', rate: 0.00868, source: 'Yahoo' }, // newest JPY
];

test('latestRateMap picks the most recent date per currency + SGD = 1', () => {
  const m = latestRateMap(rates);
  expect(m.get('USD')).toBeCloseTo(1.341, 4);
  expect(m.get('JPY')).toBeCloseTo(0.00868, 6);
  expect(m.get('SGD')).toBe(1);
});

test('convertViaRates: same currency → identity', () => {
  const m = latestRateMap(rates);
  expect(convertViaRates(123.45, 'USD', 'USD', m)).toBe(123.45);
});

test('convertViaRates pivots through SGD using latest rates', () => {
  const m = latestRateMap(rates);
  // 100 USD → SGD = 100 * 1.341 = 134.1
  expect(convertViaRates(100, 'USD', 'SGD', m)).toBeCloseTo(134.1, 4);
  // 1000 JPY → USD = 1000 * 0.00868 / 1.341 ≈ 6.4728
  expect(convertViaRates(1000, 'JPY', 'USD', m)!).toBeCloseTo((1000 * 0.00868) / 1.341, 4);
});

test('convertViaRates returns null when a currency is unknown', () => {
  const m = latestRateMap(rates);
  expect(convertViaRates(100, 'USD', 'XYZ', m)).toBeNull();
  expect(convertViaRates(100, 'ABC', 'SGD', m)).toBeNull();
});
