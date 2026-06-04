// Throwaway script — run with `bun scripts/check-pending-matches.ts` from
// the frontend/ directory. Lists what the matcher produces for the seeded
// pending transactions plus a few bank-munged demos, so you can predict what
// you'll see in the browser before opening the Pending page.
import { matchCounterparty } from '@/lib/matcher/counterparty';
import counterpartiesData from '@/data/counterparties.json';

const CATALOG = (counterpartiesData as Array<{ id: string; name: string; verified: number }>).map((c) => ({
  id: c.id,
  name: c.name,
  verified: c.verified === 1,
}));

const samples = [
  // The four seeded pending transactions
  'Lyft',                  // 2026-05-23 — no match in catalog
  'Salary · Acme',         // 2026-05-25 — no match in catalog
  'Don Don Donki',         // 2026-05-24 — exact match to cp-04 (UNVERIFIED)
  'Sushiro · Tangs',       // 2026-05-24 — partial: anchor on Sushiro (cp-06, UNVERIFIED), extra "Tangs" not in catalog
  // Bank-munged demos
  'GRAB',                  // single-token, verified
  'NETFLIX.COM*SUB',       // domain suffix + processor-style sub
  'STARBUCKS SUNTEC #4521',// location + order number
  'BLUE BOTTLE COFFEE MARINA', // brand new
];

for (const raw of samples) {
  const m = matchCounterparty(raw, CATALOG);
  let extra = '';
  if (m.kind === 'verified' || m.kind === 'unverified') {
    extra = ` → ${m.candidate.name} [${m.candidate.reason}, score ${m.candidate.score.toFixed(2)}]`;
  } else if (m.kind === 'ambiguous') {
    extra = ` → ${m.candidates.map((c) => `${c.name} (${c.score.toFixed(2)})`).join(' | ')}`;
  } else if (m.kind === 'none') {
    extra = ` → suggested "${m.suggestedName}"`;
  }
  console.log(raw.padEnd(28), '→', m.kind.padEnd(11), extra);
}
