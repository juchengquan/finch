import { test, expect } from 'bun:test';
import { createRule } from '@/lib/db/queries/rules';
import { insertTxRow } from '@/lib/db/queries/transactions';
import { seededDb } from '../db/core/test-utils';
import type { Exec } from '../db/core/repo';
import type { Action, Condition } from '@/lib/rules/types';

async function seeded(): Promise<Exec> {
  const { exec } = await seededDb();
  return exec;
}

const baseRow = {
  ledgerId: 'personal',
  accountId: 'chk',
  date: '2026-05-15',
  amount: -40,
  description: 'Test',
  kind: 'expense' as const,
};

// Helper: given the entry id returned by insertTxRow, retrieve the category leg's
// category_id and the entry's applied_rule_ids.
async function entryMeta(exec: Exec, entryId: string): Promise<{ categoryId: string | null; appliedRuleIds: string | null; reviewedAt: string | null }> {
  const [e] = await exec('SELECT applied_rule_ids, reviewed_at FROM entries WHERE id = ?', [entryId]);
  // The category comes from the category leg (account_id IS NULL).
  const catLegs = await exec(
    'SELECT category_id FROM postings WHERE entry_id = ? AND account_id IS NULL ORDER BY sort_order',
    [entryId],
  );
  const catLeg = catLegs[0];
  return {
    categoryId: catLeg?.category_id == null ? null : String(catLeg.category_id),
    appliedRuleIds: e?.applied_rule_ids == null ? null : String(e.applied_rule_ids),
    reviewedAt: e?.reviewed_at == null ? null : String(e.reviewed_at),
  };
}

test('insertTxRow: a matching rule pre-categorises the row and records applied_rule_ids', async () => {
  const exec = await seeded();
  const cond: Condition = { field: 'merchant', op: 'contains', value: 'shell' };
  const actions: Action[] = [{ type: 'set_category', categoryId: 'trans' }];
  await createRule(exec, 'shell-fuel', { ledgerId: 'personal', condition: cond, actions });

  const id = await insertTxRow(exec, { ...baseRow, description: 'Shell #247', categoryId: null });
  const meta = await entryMeta(exec, id);
  expect(meta.categoryId).toBe('trans');
  expect(JSON.parse(meta.appliedRuleIds!)).toEqual(['shell-fuel']);
});

test('insertTxRow: amount-aware rules — Shell under $5 = Snacks, over = Fuel', async () => {
  const exec = await seeded();
  await createRule(exec, 'shell-snack', {
    ledgerId: 'personal',
    priority: 50, // lower number = runs first
    condition: {
      all: [
        { field: 'merchant', op: 'contains', value: 'shell' },
        { field: 'amount', op: 'lt', value: 5 },
      ],
    },
    actions: [{ type: 'set_category', categoryId: 'food' }],
  });
  await createRule(exec, 'shell-fuel', {
    ledgerId: 'personal',
    priority: 60,
    condition: {
      all: [
        { field: 'merchant', op: 'contains', value: 'shell' },
        { field: 'amount', op: 'gte', value: 5 },
      ],
    },
    actions: [{ type: 'set_category', categoryId: 'trans' }],
  });

  const snackId = await insertTxRow(exec, { ...baseRow, description: 'Shell', amount: -4.5 });
  const fuelId = await insertTxRow(exec, { ...baseRow, description: 'Shell', amount: -48 });
  const snack = await entryMeta(exec, snackId);
  const fuel = await entryMeta(exec, fuelId);
  expect(snack.categoryId).toBe('food');
  expect(fuel.categoryId).toBe('trans');
});

test('insertTxRow: tag-add action inserts a entry_tags row after the parent lands', async () => {
  const exec = await seeded();
  await createRule(exec, 'biz-tag', {
    ledgerId: 'personal',
    condition: { field: 'note', op: 'contains', value: 'client' },
    actions: [{ type: 'add_tag', tagId: 'tag-business' }],
  });

  const id = await insertTxRow(exec, { ...baseRow, notes: 'Lunch with client' });
  const tags = await exec(
    'SELECT tag_id FROM entry_tags WHERE entry_id = ?',
    [id],
  );
  expect(tags.map((r) => String(r.tag_id))).toEqual(['tag-business']);
});

test('insertTxRow: split-action lays down category legs summing to the parent', async () => {
  const exec = await seeded();
  await createRule(exec, 'target-split', {
    ledgerId: 'personal',
    condition: { field: 'merchant', op: 'contains', value: 'target' },
    actions: [
      {
        type: 'split',
        splits: [
          { fraction: 0.6, categoryId: 'food' },
          { fraction: 0.4, categoryId: 'shop' },
        ],
      },
    ],
  });

  const id = await insertTxRow(exec, { ...baseRow, description: 'Target', amount: -100 });
  // Category legs (account_id IS NULL) in sort_order, excluding fx-system legs.
  const catLegs = await exec(
    `SELECT p.category_id, p.amount, p.amount_base
       FROM postings p
       LEFT JOIN categories c ON c.id = p.category_id
       WHERE p.entry_id = ? AND p.account_id IS NULL AND (c.system IS NULL OR c.system != 'fx')
       ORDER BY p.sort_order`,
    [id],
  );
  expect(catLegs.map((s) => String(s.category_id))).toEqual(['food', 'shop']);
  // Sum of category leg amounts (negated — category legs are the balancing side).
  const sum = catLegs.reduce((s, r) => s + Number(r.amount), 0);
  // Category legs are negative of the account leg (balance to 0). Sum ≈ +100.
  expect(Math.abs(Math.round(sum * 100) / 100)).toBe(100);
});

test('insertTxRow: skipRules bypasses the engine entirely', async () => {
  const exec = await seeded();
  await createRule(exec, 'shell-fuel', {
    ledgerId: 'personal',
    condition: { field: 'merchant', op: 'contains', value: 'shell' },
    actions: [{ type: 'set_category', categoryId: 'trans' }],
  });
  const id = await insertTxRow(exec, {
    ...baseRow,
    description: 'Shell',
    categoryId: 'misc',
    skipRules: true,
  });
  const meta = await entryMeta(exec, id);
  expect(meta.categoryId).toBe('misc'); // untouched
  expect(meta.appliedRuleIds).toBeNull();
});

test('insertTxRow: an inactive rule does not contribute', async () => {
  const exec = await seeded();
  await createRule(exec, 'off', {
    ledgerId: 'personal',
    isActive: false,
    condition: { field: 'merchant', op: 'contains', value: 'shell' },
    actions: [{ type: 'set_category', categoryId: 'trans' }],
  });
  const id = await insertTxRow(exec, { ...baseRow, description: 'Shell', categoryId: 'misc' });
  const meta = await entryMeta(exec, id);
  expect(meta.categoryId).toBe('misc');
  expect(meta.appliedRuleIds).toBeNull();
});

test('insertTxRow: rule from a different ledger does not fire', async () => {
  const exec = await seeded();
  await createRule(exec, 'fam-tag', {
    ledgerId: 'family', // not 'personal'
    condition: { field: 'merchant', op: 'contains', value: 'shell' },
    actions: [{ type: 'set_category', categoryId: 'food' }],
  });
  const id = await insertTxRow(exec, { ...baseRow, description: 'Shell', categoryId: 'misc' });
  const meta = await entryMeta(exec, id);
  expect(meta.categoryId).toBe('misc');
});

test('insertTxRow: a later (higher-priority-number) rule overrides an earlier set_category', async () => {
  const exec = await seeded();
  await createRule(exec, 'early', {
    ledgerId: 'personal',
    priority: 10,
    condition: { field: 'merchant', op: 'contains', value: 'whole' },
    actions: [{ type: 'set_category', categoryId: 'food' }],
  });
  await createRule(exec, 'late', {
    ledgerId: 'personal',
    priority: 100,
    condition: { field: 'merchant', op: 'contains', value: 'whole' },
    actions: [{ type: 'set_category', categoryId: 'shop' }],
  });
  const id = await insertTxRow(exec, { ...baseRow, description: 'Whole Foods' });
  const meta = await entryMeta(exec, id);
  expect(meta.categoryId).toBe('shop');
  // Both ids in apply order — losing rule still recorded.
  expect(JSON.parse(meta.appliedRuleIds!)).toEqual(['early', 'late']);
});

test('insertTxRow: a mark_reviewed rule stamps reviewed_at at insert', async () => {
  const exec = await seeded();
  await createRule(exec, 'auto-review', {
    ledgerId: 'personal',
    condition: { field: 'merchant', op: 'contains', value: 'netflix' },
    actions: [{ type: 'mark_reviewed' }],
  });
  const reviewed = await insertTxRow(exec, { ...baseRow, description: 'Netflix' });
  const unreviewed = await insertTxRow(exec, { ...baseRow, description: 'Spotify' });
  const rev = await entryMeta(exec, reviewed);
  const unrev = await entryMeta(exec, unreviewed);
  expect(rev.reviewedAt).not.toBeNull();
  expect(unrev.reviewedAt).toBeNull(); // no matching rule → stays unreviewed
});
