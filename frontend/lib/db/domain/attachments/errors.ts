// lib/db/domain/attachments/errors.ts — I18nError codes for the
// attachments domain. Imported by queries.ts and (in PR 4) by
// mutations.ts so a typo in a code becomes a tsc error, not a runtime
// miss.

export const ATTACHMENT_ERROR_CODES = {
  invalidKind: 'error.attachment.invalidKind',
} as const;
