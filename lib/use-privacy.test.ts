import { test, expect } from 'bun:test';
import { parsePrivacyRaw, MONEY_MASK } from './use-privacy';

test('parsePrivacyRaw: only the literal "1" turns privacy on', () => {
  expect(parsePrivacyRaw('1')).toBe(true);
  expect(parsePrivacyRaw('0')).toBe(false);
  expect(parsePrivacyRaw(null)).toBe(false); // unset — default off
  expect(parsePrivacyRaw('true')).toBe(false); // legacy/hand-edited junk stays off
  expect(parsePrivacyRaw('')).toBe(false);
});

test('MONEY_MASK carries no digits or currency information', () => {
  expect(MONEY_MASK).not.toMatch(/[0-9$€£¥]/);
  expect(MONEY_MASK.length).toBeGreaterThan(0);
});
