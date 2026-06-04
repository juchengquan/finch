// Rule-based counterparty matcher.
//
// A bank statement line ("NETFLIX.COM*SUB 1234") needs to be resolved to a
// catalog row ("Netflix"). The pipeline is:
//
//   1. Normalize — strip domain suffixes, payment-processor tags, order
//      numbers, punctuation, legal suffixes. Both sides (the raw string and
//      each candidate catalog name) go through the same pipeline so they
//      become comparable.
//   2. Tokenize — split on whitespace, drop stop words.
//   3. Anchor — the first non-stop token of a candidate is its brand word.
//      The matcher rejects any candidate whose anchor is missing from the
//      raw tokens (so "Don Don Donki" never matches "Starbucks" just because
//      both contain "don").
//   4. Score — for each surviving candidate, score ∈ [0, 1] by how many of
//      its tokens appear in the raw. Top two must be far enough apart or the
//      result is "ambiguous" and the user picks.
//   5. Bucket — the score + verification flag maps to one of four outcomes
//      the UI can render directly.
//
// Deterministic, explainable, no library. Pure: no React, no DOM, no I/O.
// Safe to call on every pending row on every render.

/** Catalog row, projected shape (mirrors `Counterparty` from queries/counterparties). */
export interface CatalogEntry {
  id: string;
  name: string;
  verified: boolean;
}

export interface MatchCandidate {
  id: string;
  name: string;
  verified: boolean;
  /** Match score in [0, 1]. */
  score: number;
  /** Human-readable reason, useful for tooltips + tests. */
  reason: MatchReason;
}

export type MatchReason =
  | 'full-token-match'
  | 'partial-token-match'
  | 'anchor-prefix'
  | 'substring'
  | 'typo';

export type Match =
  | { kind: 'verified'; candidate: MatchCandidate }
  | { kind: 'unverified'; candidate: MatchCandidate }
  | { kind: 'ambiguous'; candidates: MatchCandidate[] }
  | { kind: 'none'; suggestedName: string };

export interface MatchOptions {
  /** Maximum number of candidates to return for an ambiguous match. Default 3. */
  maxAmbiguous?: number;
  /** Minimum score gap between the top two to avoid spurious ambiguities. Default 0.15. */
  ambiguityGap?: number;
  /** Below this score, the candidate is treated as "no match". Default 0.5. */
  minScore?: number;
}

const DEFAULT_OPTS: Required<MatchOptions> = {
  maxAmbiguous: 3,
  ambiguityGap: 0.15,
  minScore: 0.5,
};

// Words that are useless for distinguishing merchants. Includes common legal
// suffixes — they survive the digit-strip but don't identify a brand.
const STOP_WORDS = new Set([
  'a', 'an', 'the', 'and', 'or', 'of', 'at', 'in', 'on',
  'ltd', 'pte', 'inc', 'llc', 'co', 'cooperative', 'operative', 'company', 'corporation', 'corp',
  'group', 'holdings', 'limited',
  'restaurant', 'cafe', 'cafeteria', 'kitchen', 'bar', 'grill',
  'store', 'shop', 'market', 'mart', 'outlet',
  'mktp', 'online', 'web',
  'sg', 'uk', 'us', 'au',
]);

const DOMAIN_SUFFIX_RE = /\.(com|net|co|org|io|app|sg|uk|au|jp|cn|my|th|ph|id|in)\b/gi;
const PROCESSOR_PREFIX_RE = /\b(?:sq\*|tst\*|paypal\*|amzn|amzn\s*mktp|goog\*|apple\.com\/bill)\b/gi;
const ORDER_HASH_RE = /#\d+\b/g;
const ORDER_CODE_RE = /\b(?:ord|order|ref|po|invoice|inv)[-_]?\d+\b/gi;
const LONG_DIGIT_RUN_RE = /\b\d{4,}\b/g;
const PUNCT_RE = /[*\/.,;:_'"`~^()\[\]{}<>\\|&+-]+/g;
const WHITESPACE_RE = /\s+/g;

/** Normalize a free-text merchant string for comparison. Pure. */
export function normalize(s: string): string {
  return s
    .toLowerCase()
    .replace(DOMAIN_SUFFIX_RE, ' ')
    .replace(PROCESSOR_PREFIX_RE, ' ')
    .replace(ORDER_HASH_RE, ' ')
    .replace(ORDER_CODE_RE, ' ')
    .replace(LONG_DIGIT_RUN_RE, ' ')
    .replace(PUNCT_RE, ' ')
    .replace(WHITESPACE_RE, ' ')
    .trim();
}

/** Normalize + tokenize + drop stop words. */
export function tokenize(s: string): string[] {
  const norm = normalize(s);
  if (!norm) return [];
  return norm.split(' ').filter((t) => t.length > 0 && !STOP_WORDS.has(t));
}

/** Title-case a phrase for the "suggest new merchant name" default. */
export function titleCase(s: string): string {
  return s
    .split(' ')
    .filter(Boolean)
    .map((w) => (w.length <= 2 && /^\d+$/.test(w) ? w : w.charAt(0).toUpperCase() + w.slice(1)))
    .join(' ');
}

/** Levenshtein distance, small-string-only. Used for the typo branch. */
function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  // Two-row DP, fine for ≤ 32-char tokens.
  const prev = new Array(b.length + 1);
  const curr = new Array(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1;
      curr[j] = Math.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
    }
    for (let j = 0; j <= b.length; j++) prev[j] = curr[j];
  }
  return prev[b.length];
}

interface ScoredCandidate {
  c: CatalogEntry;
  tokens: string[];
  score: number;
  reason: MatchReason;
}

function scoreCandidate(rawTokens: string[], candTokens: string[]): { score: number; reason: MatchReason } {
  if (candTokens.length === 0) return { score: 0, reason: 'typo' };
  const anchor = candTokens[0];
  const anchorIdx = rawTokens.indexOf(anchor);
  if (anchorIdx === -1) {
    // Anchor absent — try a typo on the anchor as a last resort.
    for (const t of rawTokens) {
      if (t.length >= 3 && Math.abs(t.length - anchor.length) <= 2 && levenshtein(anchor, t) <= 2) {
        return { score: 0.6, reason: 'typo' };
      }
    }
    return { score: 0, reason: 'typo' };
  }

  const remaining = candTokens.slice(1);

  // (1) Full token set match.
  if (remaining.every((t) => rawTokens.includes(t))) {
    return { score: 1.0, reason: 'full-token-match' };
  }

  // (2) Partial token match (≥ 80% of remaining tokens present).
  if (remaining.length > 0) {
    const hit = remaining.filter((t) => rawTokens.includes(t)).length;
    const ratio = hit / remaining.length;
    if (ratio >= 0.8) return { score: 0.85, reason: 'partial-token-match' };
  }

  // (3) Anchor-only on a single-token candidate: catalog row is exactly the
  //     anchor (e.g. catalog "Grab", raw "GRAB FOOD DELIVERY"). The candidate
  //     is broader than the raw, so it's a *partial* match — the user might
  //     mean a more specific row. Score 0.7.
  if (remaining.length === 0) {
    return { score: 0.7, reason: 'anchor-prefix' };
  }

  // (4) Anchor present but the candidate has extra tokens that the raw
  //     doesn't. E.g. catalog "Starbucks Suntec", raw "STARBUCKS". The
  //     candidate is more specific than the raw — possibly the right one,
  //     possibly a sibling ("Starbucks Marina"). Score 0.65; combined with
  //     the ambiguity gap, two siblings land in the ambiguous bucket.
  if (rawTokens.length === 1) {
    return { score: 0.65, reason: 'partial-token-match' };
  }

  // (5) Substring fallback: the candidate's tokens, joined, appear in the
  //     raw's normalized form. Catches adjacent tokens that got reordered.
  const candJoined = candTokens.join(' ');
  const rawJoined = rawTokens.join(' ');
  if (candJoined.length >= 3 && rawJoined.includes(candJoined)) {
    return { score: 0.75, reason: 'substring' };
  }

  return { score: 0, reason: 'typo' };
}

/** Public entry point. */
export function matchCounterparty(raw: string, catalog: CatalogEntry[], options: MatchOptions = {}): Match {
  const opts = { ...DEFAULT_OPTS, ...options };

  const rawTokens = tokenize(raw);

  // Edge case: nothing to anchor on.
  if (rawTokens.length === 0 || (rawTokens.length === 1 && rawTokens[0].length <= 2)) {
    return { kind: 'none', suggestedName: '' };
  }

  // Edge case: empty catalog.
  if (catalog.length === 0) {
    return { kind: 'none', suggestedName: titleCase(rawTokens.join(' ')) };
  }

  const scored: ScoredCandidate[] = [];
  for (const c of catalog) {
    const tokens = tokenize(c.name);
    if (tokens.length === 0) continue;
    const { score, reason } = scoreCandidate(rawTokens, tokens);
    if (score >= opts.minScore) scored.push({ c, tokens, score, reason });
  }

  scored.sort((a, b) => b.score - a.score);

  if (scored.length === 0) {
    return { kind: 'none', suggestedName: suggestNameFromRaw(rawTokens) };
  }

  const [best, second] = scored;
  if (second && best.score - second.score < opts.ambiguityGap) {
    return {
      kind: 'ambiguous',
      candidates: scored.slice(0, opts.maxAmbiguous).map(toMatchCandidate),
    };
  }

  return best.c.verified
    ? { kind: 'verified', candidate: toMatchCandidate(best) }
    : { kind: 'unverified', candidate: toMatchCandidate(best) };
}

function toMatchCandidate(s: ScoredCandidate): MatchCandidate {
  return { id: s.c.id, name: s.c.name, verified: s.c.verified, score: s.score, reason: s.reason };
}

/** Default name for a "no match" — drop the trailing location-ish token when
 *  the raw has 3+ tokens, title-case the rest. v1 is intentionally simple. */
function suggestNameFromRaw(rawTokens: string[]): string {
  const cleaned = rawTokens.length >= 3 ? rawTokens.slice(0, -1) : rawTokens;
  return titleCase(cleaned.join(' '));
}
