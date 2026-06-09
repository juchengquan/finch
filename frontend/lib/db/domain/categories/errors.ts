// lib/db/domain/categories/errors.ts — I18nError codes for the
// categories domain. Imported by queries.ts (and the depth helpers
// folded into the domain) and (in PR 4) by mutations.ts so a typo in
// a code becomes a tsc error, not a runtime miss.

export const CATEGORY_ERROR_CODES = {
  depthCap: 'error.category.depthCap',
  notFound: 'error.notFound.category',
  required: {
    name: 'error.required.categoryName',
  },
} as const;
