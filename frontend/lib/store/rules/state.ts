// frontend/lib/store/rules/state.ts — rules-domain slice of the initial
// state. Pure data; the action creators (added in Task 4) live in
// rules/actions.ts.

import type { Rule } from '@/lib/rules/types';

export const rulesInitial = {
  rules: [] as Rule[],
} as const;
