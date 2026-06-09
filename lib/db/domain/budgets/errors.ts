// lib/db/domain/budgets/errors.ts — I18nError codes for the budgets
// domain. Imported by queries.ts and (in PR 4) by mutations.ts so a
// typo in a code becomes a tsc error, not a runtime miss.

export const BUDGET_ERROR_CODES = {
  notFound: 'error.notFound.budget',
  required: {
    name: 'error.required.budgetName',
  },
} as const;
