// frontend/lib/store/scheduled/state.ts — scheduled-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in scheduled/actions.ts.

import type { ScheduledTemplate } from '@/lib/store';

export const scheduledInitial = {
  scheduled: [] as ScheduledTemplate[],
} as const;
