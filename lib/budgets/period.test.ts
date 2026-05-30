import { test, expect } from 'bun:test';
import { periodOf, periodRange, nextPeriod, prevPeriod, periodLabel, type Frequency } from '@/lib/budgets/period';

// All inputs use UTC date arithmetic. The anchor only matters for biweekly;
// for everything else the periods are calendar-aligned.
const ANCHOR = '2026-01-05'; // a Monday — biweekly's natural starting point

test('periodOf — calendar-aligned frequencies', () => {
  expect(periodOf('2026-04-15', 'daily', ANCHOR)).toBe('2026-04-15');
  expect(periodOf('2026-04-15', 'monthly', ANCHOR)).toBe('2026-04');
  expect(periodOf('2026-04-15', 'quarterly', ANCHOR)).toBe('2026-Q2');
  expect(periodOf('2026-12-31', 'quarterly', ANCHOR)).toBe('2026-Q4');
  expect(periodOf('2026-01-01', 'quarterly', ANCHOR)).toBe('2026-Q1');
  expect(periodOf('2026-04-15', 'yearly', ANCHOR)).toBe('2026');
});

test('periodOf — weekly uses ISO 8601 week numbering', () => {
  // 2026-04-15 is a Wednesday → ISO week 16 of 2026.
  expect(periodOf('2026-04-15', 'weekly', ANCHOR)).toBe('2026-W16');
  // Year boundary: ISO 2026 W01 starts 2025-12-29.
  expect(periodOf('2025-12-29', 'weekly', ANCHOR)).toBe('2026-W01');
  expect(periodOf('2026-01-04', 'weekly', ANCHOR)).toBe('2026-W01');
  expect(periodOf('2026-01-05', 'weekly', ANCHOR)).toBe('2026-W02');
});

test('periodOf — biweekly anchored to a Monday buckets 14 days at a time', () => {
  // Anchor itself → BW01 bucket starts at the anchor's Monday.
  expect(periodOf(ANCHOR, 'biweekly', ANCHOR)).toBe('BW-2026-01-05');
  // 13 days after anchor → still in the same bucket.
  expect(periodOf('2026-01-18', 'biweekly', ANCHOR)).toBe('BW-2026-01-05');
  // 14 days after → next bucket.
  expect(periodOf('2026-01-19', 'biweekly', ANCHOR)).toBe('BW-2026-01-19');
  // Mid-April: 14 weeks (7 buckets) after anchor.
  expect(periodOf('2026-04-15', 'biweekly', ANCHOR)).toBe('BW-2026-04-13');
});

test('periodRange — covers periodOf round-trip', () => {
  const freqs: Frequency[] = ['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];
  const samples = ['2026-01-15', '2026-04-15', '2026-07-15', '2026-10-15'];
  for (const freq of freqs) {
    for (const sample of samples) {
      const p = periodOf(sample, freq, ANCHOR);
      const { from, to } = periodRange(p, freq);
      expect(from <= sample && sample <= to).toBe(true);
    }
  }
});

test('periodRange — known monthly / quarterly / yearly bounds', () => {
  expect(periodRange('2026-04', 'monthly')).toEqual({ from: '2026-04-01', to: '2026-04-30' });
  expect(periodRange('2026-02', 'monthly')).toEqual({ from: '2026-02-01', to: '2026-02-28' });
  // 2024 is a leap year — period range honours the calendar.
  expect(periodRange('2024-02', 'monthly')).toEqual({ from: '2024-02-01', to: '2024-02-29' });
  expect(periodRange('2026-Q2', 'quarterly')).toEqual({ from: '2026-04-01', to: '2026-06-30' });
  expect(periodRange('2026', 'yearly')).toEqual({ from: '2026-01-01', to: '2026-12-31' });
});

test('periodRange — weekly spans 7 days starting on Monday', () => {
  const { from, to } = periodRange('2026-W16', 'weekly');
  expect(from).toBe('2026-04-13'); // Monday
  expect(to).toBe('2026-04-19');   // Sunday
});

test('periodRange — biweekly spans exactly 14 days', () => {
  const { from, to } = periodRange('BW-2026-01-05', 'biweekly');
  expect(from).toBe('2026-01-05');
  expect(to).toBe('2026-01-18');
});

test('nextPeriod / prevPeriod — chronological + invertible', () => {
  const freqs: Frequency[] = ['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];
  for (const freq of freqs) {
    const p = periodOf('2026-04-15', freq, ANCHOR);
    const np = nextPeriod(p, freq, ANCHOR);
    expect(np > p).toBe(true);
    // round-trip
    expect(prevPeriod(np, freq, ANCHOR)).toBe(p);
  }
});

test('nextPeriod — crosses year boundaries', () => {
  expect(nextPeriod('2026-12', 'monthly', ANCHOR)).toBe('2027-01');
  expect(nextPeriod('2026-Q4', 'quarterly', ANCHOR)).toBe('2027-Q1');
  expect(nextPeriod('2026', 'yearly', ANCHOR)).toBe('2027');
});

test('periodLabel — human-readable headers', () => {
  expect(periodLabel('2026-04', 'monthly')).toBe('April 2026');
  expect(periodLabel('2026-Q2', 'quarterly')).toBe('2026 Q2');
  expect(periodLabel('2026', 'yearly')).toBe('2026');
  expect(periodLabel('2026-W16', 'weekly')).toBe('Week 16 · 2026');
  expect(periodLabel('BW-2026-04-13', 'biweekly')).toBe('Biweek of Apr 13');
});
