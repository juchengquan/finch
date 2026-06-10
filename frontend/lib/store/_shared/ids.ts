// frontend/lib/store/_shared/ids.ts — small ID generator for the
// per-domain action creators. Mirrors the backend's
// `lib/db/domain/_shared/ids.ts` (PR 4 Task 1).
//
// Long form: ${prefix}-${base36-timestamp}-${4-char-random-suffix}
//   Used for createX actions where a collision is theoretically possible.
// Short form: ${prefix}-${base36-timestamp}
//   Used when the server validates non-collision (e.g. updateAccount).

export function newId(prefix: string, opts?: { long?: boolean }): string {
  const ts = Date.now().toString(36);
  if (opts?.long === false) return `${prefix}-${ts}`;
  const suffix = Math.random().toString(36).slice(2, 6);
  return `${prefix}-${ts}-${suffix}`;
}
