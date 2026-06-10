// frontend/lib/store/_shared/types.ts — the (set, get) tuple types the
// per-domain action creator factories receive. Derived from zustand's
// `StateCreator<FinanceState>` so the type signatures stay in lockstep
// with the store.
//
// Usage in per-domain actions.ts:
//   import type { SetState, GetState } from '../_shared/types';
//   export const accountActions = (set: SetState, get: GetState) => ({ ... });
//
// The first two parameters of a `StateCreator<T>` are `setState` and
// `getState`; `store` (the third) is unused by the action factories.

import type { StateCreator } from 'zustand';
import type { FinanceState } from '../state';

export type SetState = Parameters<StateCreator<FinanceState>>[0];
export type GetState = Parameters<StateCreator<FinanceState>>[1];
