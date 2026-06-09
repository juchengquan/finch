import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededAndAudited } from '@/lib/db/core/test-utils';
import { listCounterparties, searchCounterparties, verifyCounterparty } from '@/lib/db/queries/counterparties';

test('counterparties: list, search, verify, alias', async () => {
  const exec = await seededAndAudited();
  expect((await listCounterparties(exec, 'personal')).length).toBeGreaterThan(0);

  const grab = await searchCounterparties(exec, 'personal', 'GRAB');
  expect(grab.some((c) => c.name === 'Grab')).toBe(true);

  const donki = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(donki.verified).toBe(false);
  await verifyCounterparty(exec, 'cp-04');
  const after = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(after.verified).toBe(true);
});

test('deleteCounterparty removes the merchant', async () => {
  const exec = await seededAndAudited();
  const cpId = String((await exec("SELECT id FROM counterparties WHERE ledger_id = 'personal' LIMIT 1"))[0].id);
  await applyMutation(exec, 'deleteCounterparty', { id: cpId });
  expect(Number((await exec('SELECT COUNT(*) AS n FROM counterparties WHERE id = ?', [cpId]))[0].n)).toBe(0);
});

test('createCounterparty inserts an unverified merchant', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createCounterparty', { id: 'cp-new', ledgerId: 'personal', name: 'Starbucks' });
  const cp = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-new')!;
  expect(cp.name).toBe('Starbucks');
  expect(cp.verified).toBe(false);
  await expect(applyMutation(exec, 'createCounterparty', { name: '  ' })).rejects.toThrow();
});
