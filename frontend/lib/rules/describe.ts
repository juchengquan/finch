// Human-readable summaries of rule conditions and actions. Used by the
// /rules page list rows + detail view. Kept pure + side-effect-free so the
// same descriptions render in tests and the future "test panel" preview.
//
// Strings are templated against a small dictionary so the page can swap in
// translated labels via `useTranslations`. Tests still get the legacy
// English defaults from `DEFAULT_DICT` when no dict is passed.

import type { Action, Condition, Leaf, SplitTemplate } from '@/lib/rules/types';

const DEFAULT_DICT = {
  weekdays: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
  fields: {
    merchant: 'merchant',
    amount: 'amount',
    account_id: 'account',
    category_id: 'category',
    counterparty_id: 'counterparty',
    currency: 'currency',
    date_dow: 'day-of-week',
    date_dom: 'day-of-month',
    kind: 'kind',
    tag_id: 'tag',
    note: 'note',
  } as Record<string, string>,
  ops: {
    is: 'is',
    isEmpty: 'is empty',
    contains: 'contains',
    startsWith: 'starts with',
    between: 'between',
    weekday: 'weekday',
    hasTag: 'has tag',
    hasAnyTag: 'has any tag in',
    hasAllTags: 'has all tags',
    noteContains: 'note contains',
  },
  conditions: {
    always: '(always)',
    never: '(never)',
    and: ' AND ',
    or: ' OR ',
    not: 'NOT ',
  },
  actions: {
    clearCategory: 'clear category',
    setCategory: 'set category →',
    clearCounterparty: 'clear counterparty',
    setCounterparty: 'set counterparty →',
    renameMerchant: 'rename merchant →',
    setNote: 'set note →',
    setKind: 'set kind →',
    addTag: 'add tag',
    removeTag: 'remove tag',
    markReviewed: 'mark reviewed',
    split: 'split:',
    uncategorized: 'uncategorized',
    noActions: '(no action)',
    separator: ' · ',
  },
};

export type DescribeDict = typeof DEFAULT_DICT;

function describeAmount(op: string, value: number | [number, number], dict: DescribeDict): string {
  if (op === 'between' && Array.isArray(value)) return `${dict.ops.between} $${value[0]} ${dict.conditions.and.trim()} $${value[1]}`;
  const v = Array.isArray(value) ? value[0] : value;
  if (op === 'gt') return `> $${v}`;
  if (op === 'gte') return `≥ $${v}`;
  if (op === 'lt') return `< $${v}`;
  if (op === 'lte') return `≤ $${v}`;
  if (op === 'eq') return `= $${v}`;
  return `${op} $${v}`;
}

function describeLeaf(leaf: Leaf, dict: DescribeDict): string {
  const f = dict.fields[leaf.field] ?? leaf.field;
  switch (leaf.field) {
    case 'merchant': {
      const insensitive = leaf.caseInsensitive === false ? '' : '~';
      if (leaf.op === 'is') return `${f} = "${leaf.value}"${insensitive}`;
      if (leaf.op === 'contains') return `${f} ${dict.ops.contains} "${leaf.value}"${insensitive}`;
      if (leaf.op === 'startsWith') return `${f} ${dict.ops.startsWith} "${leaf.value}"${insensitive}`;
      return `${f} ${leaf.op} "${leaf.value}"`;
    }
    case 'amount':
      return `${f} ${describeAmount(leaf.op, leaf.value, dict)}`;
    case 'account_id':
      if (leaf.op === 'is') return `${f} = ${leaf.value}`;
      return `${f} in {${leaf.value.join(', ')}}`;
    case 'category_id':
      if (leaf.op === 'is_null') return `${f} ${dict.ops.isEmpty}`;
      if (leaf.op === 'is') return `${f} = ${leaf.value}`;
      return `${f} in {${leaf.value.join(', ')}}`;
    case 'counterparty_id':
      if (leaf.op === 'is_null') return `${f} ${dict.ops.isEmpty}`;
      return `${f} = ${leaf.value}`;
    case 'currency':
      return `${f} = ${leaf.value}`;
    case 'date_dow':
      return `${dict.ops.weekday} in {${leaf.value.map((d) => dict.weekdays[d]).join(', ')}}`;
    case 'date_dom':
      if (leaf.op === 'eq') return `${f} = ${leaf.value}`;
      if (leaf.op === 'gte') return `${f} ≥ ${leaf.value}`;
      return `${f} ≤ ${leaf.value}`;
    case 'kind':
      if (leaf.op === 'is') return `${f} = ${leaf.value}`;
      return `${f} in {${leaf.value.join(', ')}}`;
    case 'tag_id':
      if (leaf.op === 'has') return `${dict.ops.hasTag} ${leaf.value}`;
      if (leaf.op === 'has_any') return `${dict.ops.hasAnyTag} {${leaf.value.join(', ')}}`;
      return `${dict.ops.hasAllTags} {${leaf.value.join(', ')}}`;
    case 'note':
      return `${dict.ops.noteContains} "${leaf.value}"`;
  }
}

/** Recursive: walks the AND/OR/NOT tree and turns it into a single-line
 *  parenthesised expression. Compact, predictable, no markup. */
export function describeCondition(cond: Condition, dict: DescribeDict = DEFAULT_DICT): string {
  if ('all' in cond) {
    if (!cond.all.length) return dict.conditions.always;
    return cond.all.map((c) => paren(c, describeCondition(c, dict))).join(dict.conditions.and);
  }
  if ('any' in cond) {
    if (!cond.any.length) return dict.conditions.never;
    return cond.any.map((c) => paren(c, describeCondition(c, dict))).join(dict.conditions.or);
  }
  if ('not' in cond) return `${dict.conditions.not}${paren(cond.not, describeCondition(cond.not, dict))}`;
  return describeLeaf(cond, dict);
}

function paren(cond: Condition, text: string): string {
  // Wrap nested combinators in parens; bare leaves don't need them.
  const isLeaf = 'field' in cond;
  return isLeaf ? text : `(${text})`;
}

function describeSplits(splits: SplitTemplate[], dict: DescribeDict): string {
  return splits
    .map((s) => `${Math.round(s.fraction * 100)}% → ${s.categoryId ?? dict.actions.uncategorized}`)
    .join(dict.actions.separator);
}

export function describeAction(a: Action, dict: DescribeDict = DEFAULT_DICT): string {
  switch (a.type) {
    case 'set_category':
      return a.categoryId == null ? dict.actions.clearCategory : `${dict.actions.setCategory} ${a.categoryId}`;
    case 'set_counterparty':
      return a.counterpartyId == null ? dict.actions.clearCounterparty : `${dict.actions.setCounterparty} ${a.counterpartyId}`;
    case 'set_merchant':
      return `${dict.actions.renameMerchant} "${a.merchant}"`;
    case 'set_note':
      return `${dict.actions.setNote} "${a.note}"`;
    case 'set_kind':
      return `${dict.actions.setKind} ${a.kind}`;
    case 'add_tag':
      return `${dict.actions.addTag} ${a.tagId}`;
    case 'remove_tag':
      return `${dict.actions.removeTag} ${a.tagId}`;
    case 'mark_reviewed':
      return dict.actions.markReviewed;
    case 'split':
      return `${dict.actions.split} ${describeSplits(a.splits, dict)}`;
  }
}

/** Single-line summary of a rule's full action list. */
export function describeActions(actions: Action[], dict: DescribeDict = DEFAULT_DICT): string {
  if (!actions.length) return dict.actions.noActions;
  return actions.map((a) => describeAction(a, dict)).join(dict.actions.separator);
}
