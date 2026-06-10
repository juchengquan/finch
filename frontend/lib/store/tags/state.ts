// frontend/lib/store/tags/state.ts — tags-domain slice of the initial
// state. Pure data; the action creators (added in Task 4) live in
// tags/actions.ts.

import type { Tag } from '@/lib/db/domain/tags/types';

export const tagsInitial = {
  tags: [] as Tag[],
} as const;
