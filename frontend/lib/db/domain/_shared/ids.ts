// lib/db/domain/_shared/ids.ts — small ID generator for the mutation cases
// that need to mint a new id (e.g. when the client doesn't pass one).
export function newId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}
