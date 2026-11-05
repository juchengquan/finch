// frontend/lib/store/_shared/ids.ts — small ID generator for the
// per-domain action creators. The long form IS the backend's
// `lib/db/domain/_shared/ids.ts` (PR 4 Task 1).
//
// Long form: ${prefix}-${base36-timestamp}-${12-hex-random-suffix}
//   Used for createX actions where a collision is theoretically possible.
// Short form: ${prefix}-${base36-timestamp}
//   Used when the server validates non-collision (e.g. updateAccount).

import { newId as newLongId } from '@/lib/db/domain/_shared/ids';

export function newId(prefix: string, opts?: { long?: boolean }): string {
  if (opts?.long === false) return `${prefix}-${Date.now().toString(36)}`;
  return newLongId(prefix);
}
