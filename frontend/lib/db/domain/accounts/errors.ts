// lib/db/domain/accounts/errors.ts — I18nError codes for the accounts
// domain. Imported by queries.ts and (in PR 4) by mutations.ts so a
// typo in a code becomes a tsc error, not a runtime miss.

export const ACCOUNT_ERROR_CODES = {
  hasTransactions: 'error.account.hasTransactions',
  unknownType: 'error.account.unknownType',
  required: {
    name: 'error.required.accountName',
  },
} as const;
