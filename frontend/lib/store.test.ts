import { test, expect, mock } from 'bun:test';

const mutateMock = mock(async () => {
  return {};
});

mock.module('@/lib/api-client', () => ({
  mutate: mutateMock,
  fetchState: mock(async () => ({})),
  fetchDbInfo: mock(async () => ({})),
  uploadAttachment: mock(async () => ({})),
  attachmentUrl: (id: string) => `/api/attachments/${id}`,
}));

// `syncMutation` short-circuits when `typeof window === 'undefined'`, so
// install a window-shaped object before exercising the action.
(globalThis as { window?: unknown }).window = {};

const { useFinanceStore } = await import('@/lib/store');

test('unarchiveAccount store action fires syncMutation with the right name + payload', async () => {
  mutateMock.mockClear();
  useFinanceStore.getState().unarchiveAccount('acct-xyz');
  // syncMutation is async: void import(...) → mutate(...) → setState(...).
  // Wait a few macrotask cycles so the chain settles.
  await new Promise((r) => setTimeout(r, 10));
  expect(mutateMock).toHaveBeenCalledTimes(1);
  expect(mutateMock).toHaveBeenCalledWith('unarchiveAccount', { id: 'acct-xyz' });
});
