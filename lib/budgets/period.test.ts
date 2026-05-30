import { test, expect } from 'bun:test';
import { periodOf, periodRange, nextPeriod, prevPeriod, periodLabel, type Frequency } from '@/lib/budgets/period';

// Calendar-aligned anchor for the common cases.
const ANCHOR = '2026-01-01';

test('periodOf — calendar-aligned anchors return the expected window-start', () => {
  expect(periodOf('2026-04-15', 'daily', ANCHOR)).toBe('2026-04-15');
  expect(periodOf('2026-04-15', 'monthly', ANCHOR)).toBe('2026-04-01');
  expect(periodOf('2026-04-15', 'quarterly', ANCHOR)).toBe('2026-04-01');
  expect(periodOf('2026-04-15', 'yearly', ANCHOR)).toBe('2026-01-01');
});

test('periodOf — anchor-shifted monthly periods step from start_date', () => {
  // Anchor Jan 15 → window containing Apr 15 is [Apr 15, May 14].
  expect(periodOf('2026-04-15', 'monthly', '2026-01-15')).toBe('2026-04-15');
  expect(periodOf('2026-04-14', 'monthly', '2026-01-15')).toBe('2026-03-15');
});

test('periodOf — weekly stepping from a Monday anchor lands on Mondays', () => {
  // 2026-01-05 is a Monday. Stepping every 7 days, 2026-04-15 falls in
  // the week starting 2026-04-13.
  expect(periodOf('2026-04-15', 'weekly', '2026-01-05')).toBe('2026-04-13');
});

test('periodOf — biweekly buckets 14 days at a time from anchor', () => {
  expect(periodOf('2026-01-05', 'biweekly', '2026-01-05')).toBe('2026-01-05');
  expect(periodOf('2026-01-18', 'biweekly', '2026-01-05')).toBe('2026-01-05'); // last day of bucket 1
  expect(periodOf('2026-01-19', 'biweekly', '2026-01-05')).toBe('2026-01-19'); // first day of bucket 2
});

test('periodRange — covers periodOf round-trip', () => {
  const freqs: Frequency[] = ['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];
  const anchors = [ANCHOR, '2026-01-15', '2026-01-05'];
  const samples = ['2026-01-15', '2026-04-15', '2026-07-15', '2026-10-15'];
  for (const freq of freqs) {
    for (const anchor of anchors) {
      for (const sample of samples) {
        const p = periodOf(sample, freq, anchor);
        const { from, to } = periodRange(p, freq, anchor);
        expect(from <= sample && sample <= to).toBe(true);
        // The period id IS the window's `from` date.
        expect(from).toBe(p);
      }
    }
  }
});

test('periodRange — known monthly / quarterly / yearly bounds (calendar-aligned)', () => {
  expect(periodRange('2026-04-01', 'monthly', ANCHOR)).toEqual({ from: '2026-04-01', to: '2026-04-30' });
  expect(periodRange('2026-02-01', 'monthly', ANCHOR)).toEqual({ from: '2026-02-01', to: '2026-02-28' });
  // 2024 is a leap year.
  expect(periodRange('2024-02-01', 'monthly', '2024-01-01')).toEqual({ from: '2024-02-01', to: '2024-02-29' });
  expect(periodRange('2026-04-01', 'quarterly', ANCHOR)).toEqual({ from: '2026-04-01', to: '2026-06-30' });
  expect(periodRange('2026-01-01', 'yearly', ANCHOR)).toEqual({ from: '2026-01-01', to: '2026-12-31' });
});

test('periodRange — weekly spans exactly 7 days', () => {
  const { from, to } = periodRange('2026-04-13', 'weekly', '2026-01-05');
  expect(from).toBe('2026-04-13');
  expect(to).toBe('2026-04-19');
});

test('periodRange — biweekly spans exactly 14 days', () => {
  const { from, to } = periodRange('2026-01-05', 'biweekly', '2026-01-05');
  expect(from).toBe('2026-01-05');
  expect(to).toBe('2026-01-18');
});

test('nextPeriod / prevPeriod — chronological + invertible across frequencies', () => {
  const freqs: Frequency[] = ['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];
  for (const freq of freqs) {
    const p = periodOf('2026-04-15', freq, ANCHOR);
    const np = nextPeriod(p, freq, ANCHOR);
    expect(np > p).toBe(true);
    expect(prevPeriod(np, freq, ANCHOR)).toBe(p);
  }
});

test('nextPeriod — crosses year boundaries for calendar-aligned frequencies', () => {
  expect(nextPeriod('2026-12-01', 'monthly', ANCHOR)).toBe('2027-01-01');
  expect(nextPeriod('2026-10-01', 'quarterly', ANCHOR)).toBe('2027-01-01');
  expect(nextPeriod('2026-01-01', 'yearly', ANCHOR)).toBe('2027-01-01');
});

test('periodLabel — calendar-aligned cases get pretty names', () => {
  expect(periodLabel('2026-04-01', 'monthly', '2026-01-01')).toBe('April 2026');
  expect(periodLabel('2026-04-01', 'quarterly', '2026-01-01')).toBe('2026 Q2');
  expect(periodLabel('2026-01-01', 'yearly', '2026-01-01')).toBe('2026');
});

test('periodLabel — anchor-shifted monthly falls back to a range label', () => {
  const label = periodLabel('2026-04-15', 'monthly', '2026-01-15');
  expect(label).toMatch(/Apr 15.*May 14/);
});

test('periodLabel — weekly + biweekly show date-range labels', () => {
  expect(periodLabel('2026-04-13', 'weekly', '2026-01-05')).toMatch(/Apr 13.*Apr 19/);
  expect(periodLabel('2026-01-05', 'biweekly', '2026-01-05')).toMatch(/Jan 5.*Jan 18/);
});
