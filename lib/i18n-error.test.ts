import { test, expect } from 'bun:test';
import {
  I18nError,
  toWireError,
  fromWireError,
  isI18nWireError,
  type ErrorWithI18n,
} from '@/lib/i18n-error';

test('I18nError: constructs with code, params, and English fallback', () => {
  const err = new I18nError('error.budget.amountGt0', { name: 'Groceries' }, 'Budget amount must be greater than 0');
  expect(err.code).toBe('error.budget.amountGt0');
  expect(err.params).toEqual({ name: 'Groceries' });
  expect(err.message).toBe('Budget amount must be greater than 0');
  expect(err.name).toBe('I18nError');
});

test('I18nError: fallback defaults to the code when omitted', () => {
  const err = new I18nError('error.required.name');
  expect(err.message).toBe('error.required.name');
  expect(err.params).toEqual({});
});

test('toWireError(I18nError) → structured wire shape', () => {
  const err = new I18nError('error.transfer.amountGt0', {}, 'Transfer amount must be greater than 0');
  const wire = toWireError(err);
  expect(typeof wire).toBe('object');
  expect(wire).toEqual({
    code: 'error.transfer.amountGt0',
    params: {},
    message: 'Transfer amount must be greater than 0',
  });
});

test('toWireError(plain Error) → message string (back-compat)', () => {
  const err = new Error('Something bad');
  expect(toWireError(err)).toBe('Something bad');
});

test('toWireError(unknown) → "Unknown error"', () => {
  expect(toWireError('a string')).toBe('Unknown error');
  expect(toWireError(null)).toBe('Unknown error');
});

test('isI18nWireError discriminates wire vs string vs garbage', () => {
  expect(isI18nWireError({ code: 'x', message: 'y', params: {} })).toBe(true);
  expect(isI18nWireError({ code: 'x', message: 'y' })).toBe(true);
  expect(isI18nWireError('legacy string')).toBe(false);
  expect(isI18nWireError(null)).toBe(false);
  expect(isI18nWireError({ code: 1, message: 'y' })).toBe(false);
});

test('fromWireError: structured wire → Error with .code/.params attached', () => {
  const wire = {
    code: 'error.holding.currencyMismatch',
    params: { currency: 'SGD' },
    message: 'Holding currency must match the account currency (SGD)',
  };
  const decoded = fromWireError(wire) as ErrorWithI18n;
  expect(decoded).toBeInstanceOf(Error);
  expect(decoded.message).toBe('Holding currency must match the account currency (SGD)');
  expect(decoded.code).toBe('error.holding.currencyMismatch');
  expect(decoded.params).toEqual({ currency: 'SGD' });
});

test('fromWireError: legacy string → plain Error (back-compat)', () => {
  const decoded = fromWireError('Some legacy message');
  expect(decoded).toBeInstanceOf(Error);
  expect(decoded.message).toBe('Some legacy message');
  expect((decoded as Partial<ErrorWithI18n>).code).toBeUndefined();
});

test('fromWireError: unknown shape → generic "Server error"', () => {
  const decoded = fromWireError(undefined);
  expect(decoded.message).toBe('Server error');
});

test('round-trip: I18nError → toWireError → fromWireError preserves code/params/message', () => {
  const original = new I18nError(
    'error.scheduled.installmentDone',
    { name: 'Car loan', total: 24 },
    '"Car loan" has finished its 24-payment plan',
  );
  const wire = toWireError(original);
  const decoded = fromWireError(wire) as ErrorWithI18n;
  expect(decoded.code).toBe('error.scheduled.installmentDone');
  expect(decoded.params).toEqual({ name: 'Car loan', total: 24 });
  expect(decoded.message).toBe('"Car loan" has finished its 24-payment plan');
});
