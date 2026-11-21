import { expect, test } from 'bun:test';
import { r2 } from './round';

test('r2 rounds a half-cent away from zero on both sides, as FinchCore and SQLite ROUND do', () => {
  expect(r2(-10.125)).toBe(-10.13); // Math.round alone gives -10.12
  expect(r2(10.125)).toBe(10.13);
  expect(r2(-0.005)).toBe(-0.01);
  expect(r2(1.005)).toBe(1); // 1.005 is 1.00499… in binary: not a tie
  expect(r2(-0.001)).toBe(0);
  expect(Object.is(r2(-0.001), -0)).toBe(false);
  expect(r2(0)).toBe(0);
  expect(r2(1234.5678)).toBe(1234.57);
});
