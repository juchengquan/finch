// frontend/lib/store/transfers/state.ts — transfers-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in transfers/actions.ts. Note: transfers aren't a separate top-level
// state key — they live inside `transactions` as two rows sharing a
// `transferGroupId` — so this slice is intentionally empty for now.

export const transfersInitial = {} as const;
