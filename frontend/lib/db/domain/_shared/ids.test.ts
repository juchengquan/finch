import { test, expect, spyOn } from 'bun:test';
import { newId } from './ids';

// Within one millisecond the timestamp separates nothing, so the random suffix
// is the only defence against a duplicate PRIMARY KEY. Seeding writes many ids
// in the same millisecond; on the old 4-character suffix this collided in CI
// (`UNIQUE constraint failed: categories.id` from ensureSystemCategories).
test('newId: 100_000 ids minted in one millisecond are all distinct', () => {
  const now = spyOn(Date, 'now').mockReturnValue(1_700_000_000_000);
  try {
    const ids = new Set<string>();
    for (let i = 0; i < 100_000; i++) ids.add(newId('cat'));
    expect(ids.size).toBe(100_000);
  } finally {
    now.mockRestore();
  }
});

// Same shape as FinchCore's Entries.newId: prefix-<ms base36>-<12 hex>.
test('newId: prefix, base-36 timestamp, 12-hex-character random suffix', () => {
  for (let i = 0; i < 1000; i++) {
    expect(newId('cat')).toMatch(/^cat-[0-9a-z]+-[0-9a-f]{12}$/);
  }
});
