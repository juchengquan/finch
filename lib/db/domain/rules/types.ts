// lib/db/domain/rules/types.ts — public patch input shape for the rules
// domain. Keep this file free of SQL imports — it should be safe to import
// from any layer (UI components, route handlers, app_state) without pulling
// in the DB driver.
//
// The richer shapes (`Rule`, `NewRule`, `Condition`, `Action`) live in
// `@/lib/rules/types` and are imported directly from there. Only
// `RulePatchInput` — the editable subset on existing rules — lives here,
// because the dispatcher's `updateRule` action consumes it.

import type { Condition, Action } from '@/lib/rules/types';

export interface RulePatchInput {
  name?: string | null;
  priority?: number;
  condition?: Condition;
  actions?: Action[];
  isActive?: boolean;
  runOnEdit?: boolean;
}
