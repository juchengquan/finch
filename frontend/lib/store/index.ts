// frontend/lib/store/index.ts — the canonical entry point. Wires the
// per-domain state + actions into a single zustand store. The 66
// external consumers import `useFinanceStore` (and the data-type
// definitions Tx, ScheduledTemplate, etc.) from `@/lib/store`, which
// resolves to this file via the `@/*` alias and TypeScript's
// "folder wins over file" module resolution (lib/store/index.ts
// is preferred over lib/store.ts).
//
// Why this file also re-exports the data-type interfaces:
// Tx, TxSplit, TxSplitInput, ScheduledTemplate, ScheduledSplit, and
// TransferInput are used by ~30 external files (lib/select.ts,
// lib/rules/engine.ts, components/pending-row.tsx, etc.). They
// used to be declared in lib/store.ts. PR 2 Task 5 moved them to
// their owning per-domain state.ts files (transactions/state.ts,
// scheduled/state.ts, transfers/state.ts) and re-exports them
// here so the existing `import type { Tx } from '@/lib/store'`
// paths keep working unchanged.
//
// The 15 per-domain action factories are spread into a single
// store below. The order is alphabetical by domain (with _app
// last because it's the cross-cutting "app state" slice, not a
// domain). Each factory is (set, get) => ({ ...actionCreators }).
// The full action list lives in
// docs/superpowers/plans/2026-06-09-frontend-refactor-pr2-store-slices.md
// §"The action map (~75 actions, by domain)".

import { create } from 'zustand';
import { initialState } from './initial';
import type { FinanceState } from './state';

import { accountActions } from './accounts/actions';
import { accountGroupActions } from './accountGroups/actions';
import { budgetActions } from './budgets/actions';
import { budgetGroupActions } from './budgetGroups/actions';
import { categoryActions } from './categories/actions';
import { counterpartyActions } from './counterparties/actions';
import { fxActions } from './fx/actions';
import { holdingActions } from './holdings/actions';
import { ledgerActions } from './ledgers/actions';
import { ruleActions } from './rules/actions';
import { scheduledActions } from './scheduled/actions';
import { tagActions } from './tags/actions';
import { transactionActions } from './transactions/actions';
import { transferActions } from './transfers/actions';
import { appActions } from './_app/actions';

// The full store type is `FinanceState` (data) intersected with the
// return types of the 15 per-domain action factories plus the `_app`
// factory. The action signatures live with each factory in
// `<domain>/actions.ts`; the data shape lives in `./state`. We
// don't merge them into a single named type to avoid the action
// signature duplication that this PR exists to eliminate.
type FullState = FinanceState
  & ReturnType<typeof accountActions>
  & ReturnType<typeof accountGroupActions>
  & ReturnType<typeof budgetActions>
  & ReturnType<typeof budgetGroupActions>
  & ReturnType<typeof categoryActions>
  & ReturnType<typeof counterpartyActions>
  & ReturnType<typeof fxActions>
  & ReturnType<typeof holdingActions>
  & ReturnType<typeof ledgerActions>
  & ReturnType<typeof ruleActions>
  & ReturnType<typeof scheduledActions>
  & ReturnType<typeof tagActions>
  & ReturnType<typeof transactionActions>
  & ReturnType<typeof transferActions>
  & ReturnType<typeof appActions>;

export const useFinanceStore = create<FullState>()((set, get) => ({
  ...initialState,
  ...accountActions(set, get),
  ...accountGroupActions(set, get),
  ...budgetActions(set, get),
  ...budgetGroupActions(set, get),
  ...categoryActions(set, get),
  ...counterpartyActions(set, get),
  ...fxActions(set, get),
  ...holdingActions(set, get),
  ...ledgerActions(set, get),
  ...ruleActions(set, get),
  ...scheduledActions(set, get),
  ...tagActions(set, get),
  ...transactionActions(set, get),
  ...transferActions(set, get),
  ...appActions(set, get),
}));

export { syncMutation } from './hydrate';

export type { Tx, TxSplit, TxSplitInput } from './transactions/state';
export type { ScheduledTemplate, ScheduledSplit } from './scheduled/state';
export type { TransferInput } from './transfers/state';
export type { NewBudgetInput } from './budgets/actions';
