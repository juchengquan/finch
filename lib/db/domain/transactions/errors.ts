// lib/db/domain/transactions/errors.ts — I18nError codes for the
// transactions domain. Imported by queries.ts and (in PR 4) by
// mutations.ts so a typo in a code becomes a tsc error, not a
// runtime miss.

export const TRANSACTION_ERROR_CODES = {
  transferLegEdit: 'error.entry.transferLegEdit',
  splitLegEdit: 'error.entry.splitLegEdit',
} as const;
