// lib/db/domain/_shared/ids.ts — the ID generator for every row the engine
// mints (e.g. when the client doesn't pass one).
//
// `prefix-<ms timestamp, base36>-<12 random hex>`, the same shape as
// FinchCore's Entries.newId. Within one millisecond the timestamp separates
// nothing, so the suffix is the only defence against a duplicate PRIMARY KEY.
// It was 4 base-36 characters (~21 bits): 100_000 ids in one millisecond held
// ~2_900 duplicates, and seeding hit `UNIQUE constraint failed: categories.id`
// in CI. 48 bits from crypto.getRandomValues puts that batch at ~2e-5.
export function newId(prefix: string): string {
  const rand = Array.from(crypto.getRandomValues(new Uint8Array(6)), (b) => b.toString(16).padStart(2, '0')).join('');
  return `${prefix}-${Date.now().toString(36)}-${rand}`;
}
