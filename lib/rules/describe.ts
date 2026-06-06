// Human-readable summaries of rule conditions and actions. Used by the
// /rules page list rows + detail view. Kept pure + side-effect-free so the
// same descriptions render in tests and the future "test panel" preview.

import type { Action, Condition, Leaf, SplitTemplate } from '@/lib/rules/types';

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function describeAmount(op: string, value: number | [number, number]): string {
  if (op === 'between' && Array.isArray(value)) return `between $${value[0]} and $${value[1]}`;
  const v = Array.isArray(value) ? value[0] : value;
  if (op === 'gt') return `> $${v}`;
  if (op === 'gte') return `≥ $${v}`;
  if (op === 'lt') return `< $${v}`;
  if (op === 'lte') return `≤ $${v}`;
  if (op === 'eq') return `= $${v}`;
  return `${op} $${v}`;
}

const fieldLabel: Record<string, string> = {
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
};

function describeLeaf(leaf: Leaf): string {
  const f = fieldLabel[leaf.field] ?? leaf.field;
  switch (leaf.field) {
    case 'merchant': {
      const insensitive = leaf.caseInsensitive === false ? '' : '~';
      if (leaf.op === 'is') return `${f} = "${leaf.value}"${insensitive}`;
      if (leaf.op === 'contains') return `${f} contains "${leaf.value}"${insensitive}`;
      if (leaf.op === 'startsWith') return `${f} starts with "${leaf.value}"${insensitive}`;
      return `${f} ${leaf.op} "${leaf.value}"`;
    }
    case 'amount':
      return `${f} ${describeAmount(leaf.op, leaf.value)}`;
    case 'account_id':
      if (leaf.op === 'is') return `${f} = ${leaf.value}`;
      return `${f} in {${leaf.value.join(', ')}}`;
    case 'category_id':
      if (leaf.op === 'is_null') return `${f} is empty`;
      if (leaf.op === 'is') return `${f} = ${leaf.value}`;
      return `${f} in {${leaf.value.join(', ')}}`;
    case 'counterparty_id':
      if (leaf.op === 'is_null') return `${f} is empty`;
      return `${f} = ${leaf.value}`;
    case 'currency':
      return `${f} = ${leaf.value}`;
    case 'date_dow':
      return `weekday in {${leaf.value.map((d) => WEEKDAYS[d]).join(', ')}}`;
    case 'date_dom':
      if (leaf.op === 'eq') return `day-of-month = ${leaf.value}`;
      if (leaf.op === 'gte') return `day-of-month ≥ ${leaf.value}`;
      return `day-of-month ≤ ${leaf.value}`;
    case 'kind':
      if (leaf.op === 'is') return `kind = ${leaf.value}`;
      return `kind in {${leaf.value.join(', ')}}`;
    case 'tag_id':
      if (leaf.op === 'has') return `has tag ${leaf.value}`;
      if (leaf.op === 'has_any') return `has any tag in {${leaf.value.join(', ')}}`;
      return `has all tags {${leaf.value.join(', ')}}`;
    case 'note':
      return `note contains "${leaf.value}"`;
  }
}

/** Recursive: walks the AND/OR/NOT tree and turns it into a single-line
 *  parenthesised expression. Compact, predictable, no markup. */
export function describeCondition(cond: Condition): string {
  if ('all' in cond) {
    if (!cond.all.length) return '(always)';
    return cond.all.map((c) => paren(c, describeCondition(c))).join(' AND ');
  }
  if ('any' in cond) {
    if (!cond.any.length) return '(never)';
    return cond.any.map((c) => paren(c, describeCondition(c))).join(' OR ');
  }
  if ('not' in cond) return `NOT ${paren(cond.not, describeCondition(cond.not))}`;
  return describeLeaf(cond);
}

function paren(cond: Condition, text: string): string {
  // Wrap nested combinators in parens; bare leaves don't need them.
  const isLeaf = 'field' in cond;
  return isLeaf ? text : `(${text})`;
}

function describeSplits(splits: SplitTemplate[]): string {
  return splits
    .map((s) => `${Math.round(s.fraction * 100)}% → ${s.categoryId ?? 'uncategorized'}`)
    .join(' · ');
}

export function describeAction(a: Action): string {
  switch (a.type) {
    case 'set_category':
      return a.categoryId == null ? 'clear category' : `set category → ${a.categoryId}`;
    case 'set_counterparty':
      return a.counterpartyId == null ? 'clear counterparty' : `set counterparty → ${a.counterpartyId}`;
    case 'set_merchant':
      return `rename merchant → "${a.merchant}"`;
    case 'set_note':
      return `set note → "${a.note}"`;
    case 'set_kind':
      return `set kind → ${a.kind}`;
    case 'add_tag':
      return `add tag ${a.tagId}`;
    case 'remove_tag':
      return `remove tag ${a.tagId}`;
    case 'mark_reviewed':
      return 'mark reviewed';
    case 'split':
      return `split: ${describeSplits(a.splits)}`;
  }
}

/** Single-line summary of a rule's full action list. */
export function describeActions(actions: Action[]): string {
  if (!actions.length) return '(no action)';
  return actions.map(describeAction).join(' · ');
}
