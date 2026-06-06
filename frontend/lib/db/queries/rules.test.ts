import { test, expect } from 'bun:test';
import {
  listRules,
  listActiveRules,
  createRule,
  updateRule,
  deleteRule,
  markRuleApplied,
} from '@/lib/db/queries/rules';
import { freshDb as freshTestDb } from '@/lib/db/test-utils';
import type { Exec } from '@/lib/db/repo';
import type { Condition, Action } from '@/lib/rules/types';

async function freshDb(): Promise<Exec> {
  const { exec } = await freshTestDb();
  // A ledger to satisfy the rules.ledger_id FK.
  await exec(
    `INSERT INTO ledgers (id, name, base_currency, created_at, updated_at)
     VALUES ('personal','Personal','USD',datetime('now'),datetime('now'))`,
  );
  return exec;
}

const cond: Condition = {
  all: [
    { field: 'merchant', op: 'contains', value: 'shell', caseInsensitive: true },
    { field: 'amount', op: 'lt', value: 10 },
  ],
};
const actions: Action[] = [{ type: 'set_category', categoryId: 'snacks' }];

test('createRule + listRules round-trips the condition tree and actions through JSON', async () => {
  const exec = await freshDb();
  await createRule(exec, 'r1', { ledgerId: 'personal', name: 'Shell snacks', condition: cond, actions });
  const rules = await listRules(exec, 'personal');
  expect(rules).toHaveLength(1);
  const r = rules[0];
  expect(r.id).toBe('r1');
  expect(r.name).toBe('Shell snacks');
  expect(r.priority).toBe(100); // default
  expect(r.isActive).toBe(true);
  expect(r.runOnEdit).toBe(false); // safe default
  // Condition + actions survived the JSON boundary intact.
  expect(r.condition).toEqual(cond);
  expect(r.actions).toEqual(actions);
});

test('listActiveRules excludes inactive rules and orders by priority', async () => {
  const exec = await freshDb();
  await createRule(exec, 'lo', { ledgerId: 'personal', priority: 50, condition: cond, actions });
  await createRule(exec, 'hi', { ledgerId: 'personal', priority: 200, condition: cond, actions });
  await createRule(exec, 'off', { ledgerId: 'personal', priority: 10, condition: cond, actions, isActive: false });

  const active = await listActiveRules(exec, 'personal');
  expect(active.map((r) => r.id)).toEqual(['lo', 'hi']); // 'off' excluded; priority order
});

test('updateRule patches individual fields without disturbing the rest', async () => {
  const exec = await freshDb();
  await createRule(exec, 'r1', { ledgerId: 'personal', name: 'orig', condition: cond, actions });

  const newActions: Action[] = [
    { type: 'set_category', categoryId: 'fuel' },
    { type: 'add_tag', tagId: 'commute' },
  ];
  await updateRule(exec, 'r1', { name: 'renamed', actions: newActions, runOnEdit: true, priority: 5 });

  const [r] = await listRules(exec, 'personal');
  expect(r.name).toBe('renamed');
  expect(r.priority).toBe(5);
  expect(r.runOnEdit).toBe(true);
  expect(r.actions).toEqual(newActions);
  expect(r.condition).toEqual(cond); // untouched
});

test('deleteRule removes the row', async () => {
  const exec = await freshDb();
  await createRule(exec, 'r1', { ledgerId: 'personal', condition: cond, actions });
  await deleteRule(exec, 'r1');
  expect(await listRules(exec, 'personal')).toHaveLength(0);
});

test('markRuleApplied stamps last_applied_at', async () => {
  const exec = await freshDb();
  await createRule(exec, 'r1', { ledgerId: 'personal', condition: cond, actions });
  expect((await listRules(exec, 'personal'))[0].lastAppliedAt).toBeNull();
  await markRuleApplied(exec, 'r1');
  expect((await listRules(exec, 'personal'))[0].lastAppliedAt).not.toBeNull();
});

test('schema shape: rules table + index + applied_rule_ids column exist', async () => {
  const exec = await freshDb();
  const ruleCols = (await exec('PRAGMA table_info(rules)')).map((r) => String(r.name));
  expect(ruleCols).toEqual(
    expect.arrayContaining([
      'id', 'ledger_id', 'name', 'priority', 'condition', 'actions',
      'is_active', 'run_on_edit', 'last_applied_at', 'created_at', 'updated_at',
    ]),
  );
  const txnCols = (await exec('PRAGMA table_info(transactions)')).map((r) => String(r.name));
  expect(txnCols).toContain('applied_rule_ids');
  const idx = (await exec('PRAGMA index_list(rules)')).map((r) => String(r.name));
  expect(idx).toContain('idx_rules_ledger_active');
});
