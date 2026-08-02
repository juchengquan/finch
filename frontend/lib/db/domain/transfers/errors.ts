// lib/db/domain/transfers/errors.ts — I18nError codes for the
// transfers domain. Imported by queries.ts and (in PR 4) by
// mutations.ts so a typo in a code becomes a tsc error, not a
// runtime miss.

export const TRANSFER_ERROR_CODES = {
  amountGt0: 'error.transfer.amountGt0',
  sameCurrencyMismatch: 'error.transfer.sameCurrencyMismatch',
  // Same code + namespace as TRANSACTION_ERROR_CODES.splitLegEdit — both stacks
  // keep updateTransaction's and updateTransfer's split-edit refusals under the
  // pre-existing 'entry' namespace (iOS mirrors this divergence: its two guards
  // both use 'error.tx.splitLegEdit').
  splitLegEdit: 'error.entry.splitLegEdit',
} as const;
