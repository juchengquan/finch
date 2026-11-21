import { expect, test } from 'bun:test';
import { share, sharedSlices } from './structural-share';

test('an unchanged slice keeps its identity; a changed one does not', () => {
  const prev = { accounts: [{ id: 'a', name: 'Cash' }], tags: [{ id: 't', name: 'x' }] };
  const next = { accounts: [{ id: 'a', name: 'Cash' }], tags: [{ id: 't', name: 'y' }] };
  const out = sharedSlices(prev, next);
  expect(out.accounts).toBe(prev.accounts);
  expect(out.tags).not.toBe(prev.tags);
  expect(out.tags).toEqual(next.tags);
});

test('in a changed list, the items that did not change keep their identity, matched by id', () => {
  const a = { id: 'a', amount: 1, splits: [{ c: 'food', v: 1 }] };
  const b = { id: 'b', amount: 2 };
  const prev = [a, b];
  const next = [{ id: 'new', amount: 9 }, { id: 'a', amount: 1, splits: [{ c: 'food', v: 1 }] }, { id: 'b', amount: 3 }];
  const out = share(prev, next);
  expect(out).toEqual(next);
  expect(out[1]).toBe(a);       // moved down one place, still the same object
  expect(out[2]).not.toBe(b);   // its amount changed
});

test('values, nulls and missing keys are compared exactly', () => {
  expect(share({ x: null }, { x: null })).toEqual({ x: null });
  const prev = { x: 1, y: 2 };
  expect(share(prev, { x: 1 })).toEqual({ x: 1 });
  expect(share(prev, { x: 1 })).not.toBe(prev);
  expect(share(prev, { x: 1, y: 2 })).toBe(prev);
  expect(share([1, 2], [1, 2, 3])).toEqual([1, 2, 3]);
});
