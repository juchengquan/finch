import { test, expect } from 'bun:test';
import { occurrenceDaysInMonth, occurrencesUpTo } from '@/lib/recurrence';
import type { ScheduledTemplate } from '@/lib/store';

const T = (o: Partial<ScheduledTemplate>): ScheduledTemplate => ({
  id: 'x', name: 'x', type: 'expense', amount: 1, frequency: 'monthly', dayOfMonth: 1,
  accountId: 'a', account: 'a', autoPost: 0, nextRun: '', lastRun: '', ...o,
});

test('monthly occurrences land on dayOfMonth through the cutoff', () => {
  expect(occurrencesUpTo(T({ frequency: 'monthly', dayOfMonth: 15, startDate: '2026-01-01' }), '2026-03-31'))
    .toEqual(['2026-01-15', '2026-02-15', '2026-03-15']);
});

test('daily occurrences are bounded by endDate', () => {
  expect(occurrencesUpTo(T({ frequency: 'daily', startDate: '2026-05-01', endDate: '2026-05-03' }), '2026-05-31'))
    .toEqual(['2026-05-01', '2026-05-02', '2026-05-03']);
});

test('weekly honors a fixed weekday', () => {
  // 2026-05-01 is a Friday; first Monday (weekDay=1) is 2026-05-04.
  expect(occurrencesUpTo(T({ frequency: 'weekly', weekDay: 1, startDate: '2026-05-01' }), '2026-05-26'))
    .toEqual(['2026-05-04', '2026-05-11', '2026-05-18', '2026-05-25']);
});

test('quarterly steps three months', () => {
  expect(occurrencesUpTo(T({ frequency: 'quarterly', dayOfMonth: 1, startDate: '2026-01-01' }), '2026-12-31'))
    .toEqual(['2026-01-01', '2026-04-01', '2026-07-01', '2026-10-01']);
});

// Quarterly and yearly recur on the START DATE's day, and the start itself counts —
// whatever dayOfMonth says (a row saved without one stores 1). Mirrors
// ios/FinchCore/Tests/FinchCoreTests/ScheduledStartDayTests.swift.
test('quarterly recurs on the start day, starting with the start itself', () => {
  expect(occurrencesUpTo(T({ frequency: 'quarterly', dayOfMonth: 1, startDate: '2026-03-15' }), '2026-12-31'))
    .toEqual(['2026-03-15', '2026-06-15', '2026-09-15', '2026-12-15']);
});

test('yearly recurs on the start date', () => {
  expect(occurrencesUpTo(T({ frequency: 'yearly', dayOfMonth: 1, startDate: '2026-03-15' }), '2028-12-31'))
    .toEqual(['2026-03-15', '2027-03-15', '2028-03-15']);
});

test('a stored dayOfMonth does not move a quarterly or yearly item', () => {
  expect(occurrencesUpTo(T({ frequency: 'quarterly', dayOfMonth: 20, startDate: '2026-03-15' }), '2026-09-30'))
    .toEqual(['2026-03-15', '2026-06-15', '2026-09-15']);
  expect(occurrencesUpTo(T({ frequency: 'yearly', dayOfMonth: 0, startDate: '2026-03-15' }), '2027-12-31'))
    .toEqual(['2026-03-15', '2027-03-15']);
});

test('a quarterly or yearly start on a late day clamps to short months without drifting', () => {
  expect(occurrencesUpTo(T({ frequency: 'quarterly', startDate: '2026-03-31' }), '2027-03-31'))
    .toEqual(['2026-03-31', '2026-06-30', '2026-09-30', '2026-12-31', '2027-03-31']);
  expect(occurrencesUpTo(T({ frequency: 'yearly', startDate: '2028-02-29' }), '2030-12-31'))
    .toEqual(['2028-02-29', '2029-02-28', '2030-02-28']);
});

test('monthly still lands on its own dayOfMonth', () => {
  expect(occurrencesUpTo(T({ frequency: 'monthly', dayOfMonth: 1, startDate: '2026-03-15' }), '2026-05-31'))
    .toEqual(['2026-04-01', '2026-05-01']);
});

test('an end date still stops a quarterly item', () => {
  expect(occurrencesUpTo(T({ frequency: 'quarterly', startDate: '2026-03-15', endDate: '2026-09-14' }), '2026-12-31'))
    .toEqual(['2026-03-15', '2026-06-15']);
});

test('once yields the single start date', () => {
  expect(occurrencesUpTo(T({ frequency: 'once', startDate: '2026-05-10' }), '2026-05-30')).toEqual(['2026-05-10']);
});

test('no valid anchor → no occurrences', () => {
  expect(occurrencesUpTo(T({ startDate: undefined, nextRun: '' }), '2026-05-30')).toEqual([]);
});

test('occurrenceDaysInMonth places a quarterly item on its start day, in its months only', () => {
  const q = T({ frequency: 'quarterly', dayOfMonth: 1, startDate: '2026-03-15' });
  expect(occurrenceDaysInMonth(q, 2026, 5)).toEqual([15]); // June
  expect(occurrenceDaysInMonth(q, 2026, 6)).toEqual([]); // July
  expect(occurrenceDaysInMonth(q, 2026, 1)).toEqual([]); // February, before the start
  expect(occurrenceDaysInMonth(T({ frequency: 'yearly', startDate: '2026-03-15T09:30' }), 2027, 2)).toEqual([15]);
});
