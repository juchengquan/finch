import { afterEach, beforeEach, expect, mock, test } from 'bun:test';

// syncMutation only runs in a browser; give it a window to dispatch on.
const g = globalThis as { window?: EventTarget };
beforeEach(() => {
  g.window = new EventTarget();
});
afterEach(() => {
  delete g.window;
});

let mutateImpl: (action: string, args?: Record<string, unknown>) => Promise<unknown>;
mock.module('@/lib/api-client', () => ({
  mutate: (action: string, args?: Record<string, unknown>) => mutateImpl(action, args),
}));

const { syncMutation, SYNC_FAILED_EVENT } = await import('./hydrate');
const { useFinanceStore } = await import('./index');

function nextSyncFailure(): Promise<CustomEvent> {
  return new Promise((resolve) => {
    g.window!.addEventListener(SYNC_FAILED_EVENT, (e) => resolve(e as CustomEvent), { once: true });
  });
}

test('a rejected mutation is announced on window, not just logged', async () => {
  const rejection = Object.assign(new Error('This looks like a duplicate'), {
    code: 'error.duplicate.txn',
    params: {},
  });
  mutateImpl = async () => {
    throw rejection;
  };
  const failed = nextSyncFailure();
  const logged = console.error;
  console.error = () => {};
  try {
    syncMutation('addTransaction', { amount: -5 });
    const e = await failed;
    expect(e.detail.action).toBe('addTransaction');
    expect(e.detail.error).toBe(rejection);
  } finally {
    console.error = logged;
  }
});

test('an accepted mutation replaces the store with the server state and announces nothing', async () => {
  const serverState = { transactions: [] };
  mutateImpl = async () => serverState;
  let announced = false;
  g.window!.addEventListener(SYNC_FAILED_EVENT, () => (announced = true));
  syncMutation('setBackupRetention', { retention: 30 });
  await new Promise((r) => setTimeout(r, 10));
  expect(useFinanceStore.getState().transactions).toEqual([]);
  expect(announced).toBe(false);
});
