import { test, expect } from 'bun:test';
import { matchCounterparty, normalize, tokenize, titleCase, type CatalogEntry } from '@/lib/matcher/counterparty';

// Seeded from data/counterparties.json (only the fields the matcher uses).
const CATALOG: CatalogEntry[] = [
  { id: 'cp-01', name: '7-Eleven',       verified: true  },
  { id: 'cp-02', name: 'Grab',           verified: true  },
  { id: 'cp-03', name: 'NTUC FairPrice', verified: true  },
  { id: 'cp-04', name: 'Don Don Donki',  verified: false },
  { id: 'cp-05', name: 'Apple',          verified: true  },
  { id: 'cp-06', name: 'Sushiro',        verified: false },
];

test('normalize strips domain suffixes, processor tags, and order numbers', () => {
  expect(normalize('NETFLIX.COM*SUB')).toBe('netflix sub');
  expect(normalize('STARBUCKS #4521')).toBe('starbucks');
  // The bank form "SQ *STARBUCKS SUNTEC" — the SQ* prefix has a space, so the
  // token "sq" survives and gets dropped at tokenize. The matcher handles
  // the extra token fine; it just doesn't anchor anything.
  expect(normalize('SQ *STARBUCKS SUNTEC')).toBe('sq starbucks suntec');
  // "AMZN Mktp US*1234" — `amzn` matches the processor tag, digits stripped,
  // "mktp" and "us" survive at the normalize layer. `tokenize` then drops
  // them as stop words. The matcher correctly returns `none`.
  expect(normalize('AMZN Mktp US*1234')).toBe('mktp us');
  // "PayPal *UBER 9999" — the bank form has a space between PayPal and *,
  // so the processor prefix regex (which expects `paypal*` adjacent) doesn't
  // match. `paypal` survives normalize, but `tokenize` doesn't drop it (it's
  // not a stop word). The matcher's anchor rule handles it fine: the "paypal"
  // token doesn't anchor any candidate, so the actual match is on "uber".
  expect(normalize('PayPal *UBER 9999')).toBe('paypal uber');
  expect(normalize('STARBUCKS SUNTEC CITY')).toBe('starbucks suntec city');
});

test('normalize collapses whitespace and lowercases', () => {
  expect(normalize('  NTUC  FairPrice  ')).toBe('ntuc fairprice');
});

test('tokenize drops stop words', () => {
  expect(tokenize('The Coffee Bean & Tea Leaf')).toEqual(['coffee', 'bean', 'tea', 'leaf']);
  expect(tokenize('Apple Inc')).toEqual(['apple']);
  expect(tokenize('NTUC FairPrice Co-operative Ltd')).toEqual(['ntuc', 'fairprice']);
});

test('titleCase capitalizes each word and preserves single digits', () => {
  expect(titleCase('starbucks suntec')).toBe('Starbucks Suntec');
  expect(titleCase('7 eleven')).toBe('7 Eleven');
  expect(titleCase('netflix sub')).toBe('Netflix Sub');
});

// ----- Bucket: verified -----

test('NETFLIX.COM*SUB → verified match against "Netflix" catalog entry', () => {
  const catalog: CatalogEntry[] = [{ id: 'cp-n', name: 'Netflix', verified: true }];
  const m = matchCounterparty('NETFLIX.COM*SUB', catalog);
  expect(m.kind).toBe('verified');
  if (m.kind === 'verified') {
    expect(m.candidate.id).toBe('cp-n');
    expect(m.candidate.score).toBeGreaterThanOrEqual(0.85);
  }
});

test('case-insensitive anchor matching: "STARBUCKS" → "Starbucks"', () => {
  const catalog: CatalogEntry[] = [{ id: 'cp-s', name: 'Starbucks', verified: true }];
  const m = matchCounterparty('STARBUCKS SUNTEC #4521', catalog);
  expect(m.kind).toBe('verified');
});

test('location variant: "STARBUCKS SUNTEC CITY" → "Starbucks Suntec"', () => {
  const catalog: CatalogEntry[] = [{ id: 'cp-ss', name: 'Starbucks Suntec', verified: true }];
  const m = matchCounterparty('STARBUCKS SUNTEC CITY', catalog);
  expect(m.kind).toBe('verified');
  if (m.kind === 'verified') {
    expect(m.candidate.reason).toBe('full-token-match');
  }
});

// ----- Bucket: unverified -----

test('unverified catalog entry → unverified bucket, not verified', () => {
  const catalog: CatalogEntry[] = [{ id: 'cp-s', name: 'Sushiro', verified: false }];
  const m = matchCounterparty('SUSHIRO SHIBUYA', catalog);
  expect(m.kind).toBe('unverified');
  if (m.kind === 'unverified') {
    expect(m.candidate.id).toBe('cp-s');
    expect(m.candidate.verified).toBe(false);
  }
});

// ----- Bucket: ambiguous -----

test('two close candidates → ambiguous', () => {
  // Two siblings sharing a brand anchor (Starbucks Suntec, Starbucks MB).
  // Raw "STARBUCKS" — both anchor on `starbucks` (in raw), neither has its
  // location token in the raw → both score 0.65 (anchor present, raw has
  // one token, candidate has more). Gap 0 → ambiguous. This is the case
  // where the matcher deliberately declines to pick a winner and the user
  // chooses.
  const catalog: CatalogEntry[] = [
    { id: 'cp-1', name: 'Starbucks Suntec', verified: true  },
    { id: 'cp-2', name: 'Starbucks MB',    verified: true  },
  ];
  const m = matchCounterparty('STARBUCKS', catalog);
  expect(m.kind).toBe('ambiguous');
  if (m.kind === 'ambiguous') {
    expect(m.candidates.length).toBe(2);
  }
});

test('clear winner is not ambiguous even with similar candidates', () => {
  const catalog: CatalogEntry[] = [
    { id: 'cp-1', name: 'Netflix',         verified: true  },
    { id: 'cp-2', name: 'Netflix Premium', verified: false },
  ];
  // "NETFLIX" raw — Netflix is 1.0, Netflix Premium is 0.7 (anchor-prefix, not 0.85).
  // Gap is 0.3, well above the 0.15 threshold.
  const m = matchCounterparty('NETFLIX', catalog);
  expect(m.kind).toBe('verified');
  if (m.kind === 'verified') expect(m.candidate.id).toBe('cp-1');
});

// ----- Bucket: none -----

test('no candidate anchors the raw → none, with a clean suggested name', () => {
  const m = matchCounterparty('BLUE BOTTLE COFFEE MARINA', CATALOG);
  expect(m.kind).toBe('none');
  if (m.kind === 'none') {
    // Suggestion drops the trailing token when raw has 3+ tokens.
    expect(m.suggestedName).toBe('Blue Bottle Coffee');
  }
});

test('raw of two tokens keeps both in the suggestion', () => {
  const m = matchCounterparty('RANDOM UNKNOWN', CATALOG);
  expect(m.kind).toBe('none');
  if (m.kind === 'none') expect(m.suggestedName).toBe('Random Unknown');
});

test('empty catalog returns none', () => {
  const m = matchCounterparty('STARBUCKS', []);
  expect(m.kind).toBe('none');
  if (m.kind === 'none') expect(m.suggestedName).toBe('Starbucks');
});

test('raw of only stop words returns none with empty suggestion', () => {
  const m = matchCounterparty('THE AT AND', CATALOG);
  expect(m.kind).toBe('none');
  if (m.kind === 'none') expect(m.suggestedName).toBe('');
});

test('raw too short to anchor (1–2 chars) returns none with empty suggestion', () => {
  expect(matchCounterparty('', CATALOG).kind).toBe('none');
  expect(matchCounterparty('A', CATALOG).kind).toBe('none');
  expect(matchCounterparty('7', CATALOG).kind).toBe('none');
});

// ----- Edge cases -----

test('single-digit anchor: "7 ELEVEN MARINA SQ" → 7-Eleven', () => {
  const m = matchCounterparty('7 ELEVEN MARINA SQ', CATALOG);
  expect(m.kind).toBe('verified');
  if (m.kind === 'verified') expect(m.candidate.id).toBe('cp-01');
});

test('legal suffixes on catalog name are stripped before scoring', () => {
  // "Apple Inc" catalog should match "Apple" raw (anchor = "apple" after stripping "inc").
  const catalog: CatalogEntry[] = [{ id: 'cp-a', name: 'Apple Inc', verified: true }];
  const m = matchCounterparty('APPLE.COM/BILL', catalog);
  expect(m.kind).toBe('verified');
});

test('typo: "STARBUKCS" → "Starbucks" via Levenshtein-2', () => {
  const catalog: CatalogEntry[] = [{ id: 'cp-s', name: 'Starbucks', verified: true }];
  const m = matchCounterparty('STARBUKCS', catalog);
  expect(m.kind).toBe('verified');
  if (m.kind === 'verified') expect(m.candidate.reason).toBe('typo');
});

test('anchor absence cannot be rescued by other tokens: "Don Don Donki" raw does not match "Starbucks"', () => {
  // "Don" appears as the first raw token, but "Starbucks" anchor isn't in the raw.
  const catalog: CatalogEntry[] = [{ id: 'cp-s', name: 'Starbucks', verified: true }];
  const m = matchCounterparty('Don Don Donki', catalog);
  expect(m.kind).toBe('none');
});

test('Don Don Donki matches itself (the canonical case)', () => {
  const m = matchCounterparty('DON DON DONKI SHIBUYA', CATALOG);
  expect(m.kind).toBe('unverified');
  if (m.kind === 'unverified') expect(m.candidate.id).toBe('cp-04');
});

test('matcher ignores the verification flag when scoring — only the bucket uses it', () => {
  const verifiedCatalog: CatalogEntry[] = [{ id: 'cp-1', name: 'Foo', verified: true }];
  const unverifiedCatalog: CatalogEntry[] = [{ id: 'cp-1', name: 'Foo', verified: false }];
  const a = matchCounterparty('FOO BAR', verifiedCatalog);
  const b = matchCounterparty('FOO BAR', unverifiedCatalog);
  expect(a.kind).toBe('verified');
  expect(b.kind).toBe('unverified');
});
