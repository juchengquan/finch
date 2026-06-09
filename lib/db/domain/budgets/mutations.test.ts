import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededAndAudited } from '@/lib/db/core/test-utils';
import { I18nError } from '@/lib/i18n-error';
import { updateBudgetCycle } from '@/lib/db/domain/budgets/queries';

test('updateBudgetCycle throws I18nError when budget is not found', async () => {
  const exec = await seededAndAudited();
  await expect(
    updateBudgetCycle(exec, 'budget-nonexistent', { frequency: 'monthly', startDate: '2026-01-01', amount: 100 }),
  ).rejects.toThrow(I18nError);
});

test('duplicate guard: a second budget with the same name+cycle is rejected', async () => {
  const exec = await seededAndAudited();
  const b = { ledgerId: 'personal', name: 'Groceries', type: 'expense', amount: 600, frequency: 'monthly', startDate: '2026-05-01' };
  await applyMutation(exec, 'createBudget', { id: 'bgt-a', ...b });
  await expect(applyMutation(exec, 'createBudget', { id: 'bgt-b', ...b })).rejects.toThrow(/already exists/i);
  // Same name, different start_date (cycle) is fine.
  await applyMutation(exec, 'createBudget', { id: 'bgt-c', ...b, startDate: '2026-06-01' });
  const rows = await exec("SELECT COUNT(*) AS c FROM budgets WHERE name = 'Groceries'");
  expect(Number(rows[0].c)).toBe(2);
});
