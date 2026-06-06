import { test, expect } from 'bun:test';
import { applyRules, evaluateCondition } from '@/lib/rules/engine';
import type { Action, Condition, Leaf, Rule } from '@/lib/rules/types';
import type { Tx } from '@/lib/store';

const tx = (over: Partial<Tx>): Tx => ({
  id: Math.random().toString(36).slice(2),
  merchant: 'Whole Foods',
  category: 'food',
  amount: -84.32,
  nativeAmount: -84.32,
  currency: 'USD',
  account: 'cc',
  date: '2026-05-02', // Saturday
  pending: false,
  ledgerId: 'personal',
  kind: 'expense',
  ...over,
});

const rule = (over: Partial<Rule> & Pick<Rule, 'id' | 'condition' | 'actions'>): Rule => ({
  ledgerId: 'personal',
  name: null,
  priority: 100,
  isActive: true,
  runOnEdit: false,
  lastAppliedAt: null,
  ...over,
});

// ---------------------------------------------------------------------------
// Leaf comparators — one test per (field, op) pairing.
// ---------------------------------------------------------------------------

test('merchant: is / contains / startsWith + case-insensitive default', () => {
  const t = tx({ merchant: 'Blue Bottle Coffee' });
  expect(evaluateCondition(t, { field: 'merchant', op: 'is', value: 'blue bottle coffee' })).toBe(true);
  expect(evaluateCondition(t, { field: 'merchant', op: 'contains', value: 'BOTTLE' })).toBe(true);
  expect(evaluateCondition(t, { field: 'merchant', op: 'startsWith', value: 'Blue' })).toBe(true);
  // Case-sensitive opt-in.
  expect(evaluateCondition(t, { field: 'merchant', op: 'is', value: 'blue bottle coffee', caseInsensitive: false })).toBe(false);
  // Misses.
  expect(evaluateCondition(t, { field: 'merchant', op: 'startsWith', value: 'coffee' })).toBe(false);
});

test('amount: gt / gte / lt / lte / eq use the absolute native amount', () => {
  // amount = -84.32 (ledger-base); nativeAmount = -84.32. The engine compares |native|.
  const t = tx({ amount: -100, nativeAmount: -84.32 });
  expect(evaluateCondition(t, { field: 'amount', op: 'gt', value: 80 })).toBe(true);
  expect(evaluateCondition(t, { field: 'amount', op: 'lt', value: 85 })).toBe(true);
  expect(evaluateCondition(t, { field: 'amount', op: 'gte', value: 84.32 })).toBe(true);
  expect(evaluateCondition(t, { field: 'amount', op: 'lte', value: 84.32 })).toBe(true);
  // eq uses penny tolerance.
  expect(evaluateCondition(t, { field: 'amount', op: 'eq', value: 84.321 })).toBe(true);
  expect(evaluateCondition(t, { field: 'amount', op: 'eq', value: 90 })).toBe(false);
});

test('amount: between is inclusive on both ends', () => {
  const t = tx({ nativeAmount: -50 });
  expect(evaluateCondition(t, { field: 'amount', op: 'between', value: [50, 100] })).toBe(true);
  expect(evaluateCondition(t, { field: 'amount', op: 'between', value: [10, 50] })).toBe(true);
  expect(evaluateCondition(t, { field: 'amount', op: 'between', value: [60, 100] })).toBe(false);
});

test('amount: native takes precedence over ledger-base when both present', () => {
  // ledger-base $84, native ¥9000 — the rule should see ¥9000, not $84.
  const t = tx({ amount: -84, nativeAmount: -9000, currency: 'JPY' });
  expect(evaluateCondition(t, { field: 'amount', op: 'gt', value: 100 })).toBe(true); // 9000 > 100
  expect(evaluateCondition(t, { field: 'amount', op: 'lt', value: 100 })).toBe(false);
});

test('amount: falls back to amount when nativeAmount is absent', () => {
  const t = tx({ amount: -42, nativeAmount: undefined });
  expect(evaluateCondition(t, { field: 'amount', op: 'eq', value: 42 })).toBe(true);
});

test('account_id: is / in', () => {
  const t = tx({ account: 'chk' });
  expect(evaluateCondition(t, { field: 'account_id', op: 'is', value: 'chk' })).toBe(true);
  expect(evaluateCondition(t, { field: 'account_id', op: 'in', value: ['cc', 'chk'] })).toBe(true);
  expect(evaluateCondition(t, { field: 'account_id', op: 'in', value: ['sav'] })).toBe(false);
});

test('category_id: is / in / is_null', () => {
  expect(evaluateCondition(tx({ category: null }), { field: 'category_id', op: 'is_null' })).toBe(true);
  expect(evaluateCondition(tx({ category: 'food' }), { field: 'category_id', op: 'is_null' })).toBe(false);
  expect(evaluateCondition(tx({ category: 'food' }), { field: 'category_id', op: 'is', value: 'food' })).toBe(true);
  expect(evaluateCondition(tx({ category: 'food' }), { field: 'category_id', op: 'in', value: ['rent', 'food'] })).toBe(true);
});

test('counterparty_id: is / is_null', () => {
  const t = tx({ counterpartyId: 'cp-1' });
  expect(evaluateCondition(t, { field: 'counterparty_id', op: 'is', value: 'cp-1' })).toBe(true);
  expect(evaluateCondition(t, { field: 'counterparty_id', op: 'is_null' })).toBe(false);
  expect(evaluateCondition(tx({ counterpartyId: undefined }), { field: 'counterparty_id', op: 'is_null' })).toBe(true);
});

test('currency: is', () => {
  expect(evaluateCondition(tx({ currency: 'USD' }), { field: 'currency', op: 'is', value: 'USD' })).toBe(true);
  expect(evaluateCondition(tx({ currency: 'USD' }), { field: 'currency', op: 'is', value: 'JPY' })).toBe(false);
});

test('date_dow: in — Saturdays (2026-05-02)', () => {
  expect(evaluateCondition(tx({ date: '2026-05-02' }), { field: 'date_dow', op: 'in', value: [6] })).toBe(true);
  expect(evaluateCondition(tx({ date: '2026-05-02' }), { field: 'date_dow', op: 'in', value: [0, 6] })).toBe(true);
  expect(evaluateCondition(tx({ date: '2026-05-04' /* Mon */ }), { field: 'date_dow', op: 'in', value: [6] })).toBe(false);
});

test('date_dom: eq / gte / lte', () => {
  const t = tx({ date: '2026-05-23' });
  expect(evaluateCondition(t, { field: 'date_dom', op: 'eq', value: 23 })).toBe(true);
  expect(evaluateCondition(t, { field: 'date_dom', op: 'gte', value: 20 })).toBe(true);
  expect(evaluateCondition(t, { field: 'date_dom', op: 'lte', value: 30 })).toBe(true);
  expect(evaluateCondition(t, { field: 'date_dom', op: 'lte', value: 22 })).toBe(false);
});

test('kind: is / in (and inferred kind for legacy rows)', () => {
  expect(evaluateCondition(tx({ kind: 'income' }), { field: 'kind', op: 'is', value: 'income' })).toBe(true);
  expect(evaluateCondition(tx({ kind: 'expense' }), { field: 'kind', op: 'in', value: ['expense', 'refund'] })).toBe(true);
  // No `kind` field — infer from a transferGroupId.
  expect(
    evaluateCondition(
      tx({ kind: undefined, transferGroupId: 'tg', amount: -50 }),
      { field: 'kind', op: 'is', value: 'transfer' },
    ),
  ).toBe(true);
});

test('tag_id: has / has_any / has_all', () => {
  const t = tx({ tags: ['business', 'travel'] });
  expect(evaluateCondition(t, { field: 'tag_id', op: 'has', value: 'business' })).toBe(true);
  expect(evaluateCondition(t, { field: 'tag_id', op: 'has', value: 'personal' })).toBe(false);
  expect(evaluateCondition(t, { field: 'tag_id', op: 'has_any', value: ['x', 'travel'] })).toBe(true);
  expect(evaluateCondition(t, { field: 'tag_id', op: 'has_all', value: ['business', 'travel'] })).toBe(true);
  expect(evaluateCondition(t, { field: 'tag_id', op: 'has_all', value: ['business', 'x'] })).toBe(false);
});

test('note: contains (case-insensitive by default)', () => {
  const t = tx({ note: 'Weekly groceries' });
  expect(evaluateCondition(t, { field: 'note', op: 'contains', value: 'GROCERIES' })).toBe(true);
  expect(evaluateCondition(t, { field: 'note', op: 'contains', value: 'weekly' })).toBe(true);
  expect(evaluateCondition(tx({ note: undefined }), { field: 'note', op: 'contains', value: 'x' })).toBe(false);
});

// ---------------------------------------------------------------------------
// Combinators — all / any / not + nesting.
// ---------------------------------------------------------------------------

test('combinators: all / any / not (nested)', () => {
  const shellSnack: Condition = {
    all: [
      { field: 'merchant', op: 'contains', value: 'shell' },
      { field: 'amount', op: 'lt', value: 10 },
    ],
  };
  const fuel = tx({ merchant: 'Shell', nativeAmount: -48 });
  const snack = tx({ merchant: 'Shell', nativeAmount: -4.5 });
  expect(evaluateCondition(fuel, shellSnack)).toBe(false);
  expect(evaluateCondition(snack, shellSnack)).toBe(true);

  // any / not nesting: "is dining-out OR (Saturday AND not pending)"
  const expr: Condition = {
    any: [
      { field: 'category_id', op: 'is', value: 'dining' },
      { all: [{ field: 'date_dow', op: 'in', value: [6] }, { not: { field: 'kind', op: 'is', value: 'transfer' } }] },
    ],
  };
  expect(evaluateCondition(tx({ category: 'dining' }), expr)).toBe(true); // dining branch wins
  expect(evaluateCondition(tx({ category: 'food', date: '2026-05-02' }), expr)).toBe(true); // Saturday branch
  expect(evaluateCondition(tx({ category: 'food', date: '2026-05-04', kind: 'transfer' }), expr)).toBe(false);
});

// ---------------------------------------------------------------------------
// applyRules — the merge semantics.
// ---------------------------------------------------------------------------

const setCat = (c: string | null): Action => ({ type: 'set_category', categoryId: c });
const addTag = (id: string): Action => ({ type: 'add_tag', tagId: id });
const removeTag = (id: string): Action => ({ type: 'remove_tag', tagId: id });

test('applyRules: only matching active rules contribute; ids preserve apply order', () => {
  const r1 = rule({ id: 'r1', condition: { field: 'merchant', op: 'contains', value: 'shell' }, actions: [setCat('fuel')] });
  const r2 = rule({ id: 'r2', condition: { field: 'amount', op: 'lt', value: 5 }, actions: [setCat('snacks')] });
  const r3 = rule({ id: 'off', isActive: false, condition: { field: 'merchant', op: 'contains', value: 'shell' }, actions: [setCat('OFF')] });
  const t = tx({ merchant: 'Shell', nativeAmount: -4.5 });
  const patch = applyRules(t, [r1, r2, r3]);
  // Both fired (r1 contributes fuel, r2 overrides to snacks); inactive r3 skipped.
  expect(patch.appliedRuleIds).toEqual(['r1', 'r2']);
  // Later writer wins for set_category.
  expect(patch.categoryId).toBe('snacks');
});

test('applyRules: tag adds accumulate and dedupe; removes accumulate', () => {
  const r1 = rule({ id: 'r1', condition: { field: 'merchant', op: 'is', value: 'Whole Foods' }, actions: [addTag('groceries')] });
  const r2 = rule({ id: 'r2', condition: { field: 'category_id', op: 'is', value: 'food' }, actions: [addTag('groceries'), addTag('weekly')] });
  const r3 = rule({ id: 'r3', condition: { field: 'amount', op: 'gt', value: 50 }, actions: [removeTag('legacy')] });
  const patch = applyRules(tx({ nativeAmount: -84 }), [r1, r2, r3]);
  expect(patch.tagIdsAdd?.sort()).toEqual(['groceries', 'weekly']);
  expect(patch.tagIdsRemove).toEqual(['legacy']);
});

test('applyRules: split — first matching split wins, later splits ignored but recorded', () => {
  const splitA: Action = {
    type: 'split',
    splits: [
      { fraction: 0.6, categoryId: 'groceries' },
      { fraction: 0.4, categoryId: 'household' },
    ],
  };
  const splitB: Action = {
    type: 'split',
    splits: [{ fraction: 1.0, categoryId: 'fun' }],
  };
  const r1 = rule({ id: 'r1', condition: { field: 'merchant', op: 'contains', value: 'target' }, actions: [splitA] });
  const r2 = rule({ id: 'r2', condition: { field: 'amount', op: 'gt', value: 10 }, actions: [splitB] });
  const patch = applyRules(tx({ merchant: 'Target', nativeAmount: -200 }), [r1, r2]);
  expect(patch.splits).toEqual(splitA.splits);
  expect(patch.appliedRuleIds).toEqual(['r1', 'r2']); // both recorded even though r2's split lost
});

test('applyRules: mark_reviewed is sticky once any rule sets it', () => {
  const r1 = rule({ id: 'r1', condition: { field: 'merchant', op: 'is', value: 'x' }, actions: [{ type: 'mark_reviewed' }] });
  const r2 = rule({ id: 'r2', condition: { field: 'category_id', op: 'is', value: 'food' }, actions: [setCat('groceries')] });
  const patch = applyRules(tx({ merchant: 'x', category: 'food' }), [r1, r2]);
  expect(patch.reviewed).toBe(true);
});

test('applyRules: skipIfRuleApplied is the infinite-loop guard', () => {
  const t = tx({ appliedRuleIds: ['rA'] });
  const r = rule({ id: 'r1', condition: { field: 'merchant', op: 'contains', value: 'whole' }, actions: [setCat('x')] });
  expect(applyRules(t, [r], { skipIfRuleApplied: true }).appliedRuleIds).toEqual([]);
  // Without the guard, the rule still fires.
  expect(applyRules(t, [r]).appliedRuleIds).toEqual(['r1']);
});

test('applyRules: onEditOnly runs only rules with runOnEdit=true', () => {
  const insertOnly = rule({ id: 'ins', runOnEdit: false, condition: { field: 'merchant', op: 'is', value: 'Whole Foods' }, actions: [setCat('a')] });
  const editAlso = rule({ id: 'edit', runOnEdit: true, condition: { field: 'merchant', op: 'is', value: 'Whole Foods' }, actions: [setCat('b')] });
  expect(applyRules(tx({}), [insertOnly, editAlso], { onEditOnly: true }).appliedRuleIds).toEqual(['edit']);
  expect(applyRules(tx({}), [insertOnly, editAlso]).appliedRuleIds).toEqual(['ins', 'edit']);
});

test('applyRules: empty rules list and no-match cases return clean empty patch', () => {
  expect(applyRules(tx({}), [])).toEqual({ appliedRuleIds: [] });
  const r = rule({ id: 'r1', condition: { field: 'merchant', op: 'is', value: 'NEVER' }, actions: [setCat('x')] });
  expect(applyRules(tx({}), [r])).toEqual({ appliedRuleIds: [] });
});

test('applyRules: a single rule with multiple set actions applies them in order (last wins)', () => {
  const r = rule({
    id: 'multi',
    condition: { field: 'merchant', op: 'contains', value: 'x' },
    actions: [setCat('first'), setCat('second'), setCat('third')],
  });
  const patch = applyRules(tx({ merchant: 'xfoo' }), [r]);
  expect(patch.categoryId).toBe('third');
});

// ---------------------------------------------------------------------------
// Robustness — malformed leaves return false rather than throwing.
// ---------------------------------------------------------------------------

test('evaluateLeaf: malformed leaf op returns false rather than throwing', () => {
  // TS will catch most malformed shapes; runtime forgiveness covers JSON
  // that round-tripped through the DB with an unknown op (older rule version).
  const bad = { field: 'merchant', op: 'unknown', value: 'x' } as unknown as Leaf;
  expect(evaluateCondition(tx({}), bad)).toBe(false);
});
