import { test, expect } from 'bun:test';
import { occurrencesUpTo } from '@/lib/recurrence';
import type { ScheduledTemplate } from '@/lib/store';

const T = (o: Partial<ScheduledTemplate>): ScheduledTemplate => ({
  id: 'x', name: 'x', type: 'expense', amount: 1, frequency: 'monthly', dayOfMonth: 1,
  account: 'a', autoPost: 0, nextRun: '', lastRun: '', ...o,
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

test('once yields the single start date', () => {
  expect(occurrencesUpTo(T({ frequency: 'once', startDate: '2026-05-10' }), '2026-05-30')).toEqual(['2026-05-10']);
});

test('no valid anchor → no occurrences', () => {
  expect(occurrencesUpTo(T({ startDate: undefined, nextRun: '' }), '2026-05-30')).toEqual([]);
});
