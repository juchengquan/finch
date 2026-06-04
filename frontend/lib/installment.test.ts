import { test, expect } from 'bun:test';
import { parseInstallmentTotal } from '@/lib/installment';

test('parseInstallmentTotal: null/empty/undefined → null (no plan)', () => {
  expect(parseInstallmentTotal(null)).toBeNull();
  expect(parseInstallmentTotal(undefined)).toBeNull();
  expect(parseInstallmentTotal('')).toBeNull();
});

test('parseInstallmentTotal: positive integers pass through', () => {
  expect(parseInstallmentTotal(24)).toBe(24);
  expect(parseInstallmentTotal('12')).toBe(12);
});

test('parseInstallmentTotal: zero, negatives, fractions, NaN are rejected', () => {
  for (const bad of [0, -1, 1.5, 'abc', NaN]) {
    expect(() => parseInstallmentTotal(bad)).toThrow(
      'Installment total must be a positive whole number',
    );
  }
});
