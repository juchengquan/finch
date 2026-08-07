import { describe, expect, test } from 'bun:test';
import { minorUnits, MINOR_UNIT_EXCEPTIONS } from './currency';
import { fmtNative } from './data';

describe('ISO 4217 minor units', () => {
  test('zero-decimal currencies', () => {
    for (const code of ['JPY', 'KRW', 'VND', 'CLP', 'ISK', 'UGX', 'XOF']) {
      expect(minorUnits(code)).toBe(0);
    }
  });

  test('three-decimal currencies', () => {
    for (const code of ['BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND']) {
      expect(minorUnits(code)).toBe(3);
    }
  });

  test('default is two, unknown included', () => {
    expect(minorUnits('USD')).toBe(2);
    expect(minorUnits('EUR')).toBe(2);
    expect(minorUnits('ZZZ')).toBe(2);
  });

  test('exceptions table lists only non-2 values', () => {
    // 2 belongs to the default case; a 2 in the table is dead weight that can drift.
    for (const [code, digits] of Object.entries(MINOR_UNIT_EXCEPTIONS)) {
      expect(digits === 0 || digits === 3).toBe(true);
      expect(code).toMatch(/^[A-Z]{3}$/);
    }
  });
});

describe('fmtNative follows the table', () => {
  test('zero-decimal currency shows no cents', () => {
    // KRW fell into the "everything but JPY gets 2 digits" bucket before.
    expect(fmtNative(1234, 'KRW')).not.toContain('.');
  });

  test('three-decimal currency keeps its third digit', () => {
    expect(fmtNative(1.234, 'BHD')).toContain('1.234');
  });

  test('existing behavior unchanged for USD and JPY', () => {
    expect(fmtNative(1234.5, 'USD')).toBe('$1,234.50');
    expect(fmtNative(1234, 'JPY')).toBe('¥1,234');
  });
});
