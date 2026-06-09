// lib/db/domain/ledgers/errors.ts — I18nError codes for the ledgers
// domain. Imported by queries.ts and (in PR 4) by mutations.ts so a
// typo in a code becomes a tsc error, not a runtime miss.

export const LEDGER_ERROR_CODES = {
  notFound: 'error.notFound.ledger',
  lastLedger: 'error.ledger.lastLedger',
  recomputeFailed: 'error.ledger.recomputeFailed',
} as const;
