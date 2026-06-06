// Pure rules engine — evaluation (`evaluateCondition`) and application
// (`applyRules`) over a transaction and a list of rules. No DB, no I/O.
//
// See plans/RULES_ENGINE_PLAN.md §3-5.

import type { Tx } from '@/lib/store';
import type {
  Action,
  Condition,
  Leaf,
  Rule,
  RulePatch,
  SplitTemplate,
  TxKind,
} from '@/lib/rules/types';

// ---------------------------------------------------------------------------
// Field readers — pure projections from Tx to the comparator's input. All amount
// comparisons run against the **native** amount (account currency), matching
// the plan's principle that "users think about price in the currency they paid
// in". The native field falls back to the ledger-base `amount` when absent
// (same-currency rows omit it).
// ---------------------------------------------------------------------------

const nativeAmount = (t: Tx): number => Math.abs(t.nativeAmount ?? t.amount);

/** Tx kind, with the same legacy fallback shape used elsewhere in finch
 *  (a pre-hydration row without `kind` is inferred from transfer link + sign). */
function kindOf(t: Tx): TxKind {
  if (t.kind) return t.kind;
  if (t.transferGroupId) return 'transfer';
  return t.amount > 0 ? 'income' : 'expense';
}

/** Day of week, 0=Sun..6=Sat, from a YYYY-MM-DD string. */
function dayOfWeek(date: string): number {
  const [y, m, d] = date.slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

/** Day of month, 1..31, from a YYYY-MM-DD string. */
function dayOfMonth(date: string): number {
  return Number(date.slice(8, 10));
}

// ---------------------------------------------------------------------------
// Leaf evaluation. Each branch is a small, total function — a malformed value
// just returns false rather than throwing, so a single bad rule never breaks
// the engine for the rest.
// ---------------------------------------------------------------------------

function evaluateLeaf(t: Tx, leaf: Leaf): boolean {
  switch (leaf.field) {
    case 'merchant': {
      const m = t.merchant ?? '';
      const a = leaf.caseInsensitive === false ? m : m.toLowerCase();
      const b = leaf.caseInsensitive === false ? leaf.value : leaf.value.toLowerCase();
      if (leaf.op === 'is') return a === b;
      if (leaf.op === 'contains') return a.includes(b);
      if (leaf.op === 'startsWith') return a.startsWith(b);
      return false;
    }
    case 'amount': {
      const v = nativeAmount(t);
      if (leaf.op === 'between') {
        const [lo, hi] = leaf.value;
        return v >= lo && v <= hi;
      }
      const x = leaf.value;
      if (leaf.op === 'gt') return v > x;
      if (leaf.op === 'gte') return v >= x;
      if (leaf.op === 'lt') return v < x;
      if (leaf.op === 'lte') return v <= x;
      if (leaf.op === 'eq') return Math.abs(v - x) < 0.005;
      return false;
    }
    case 'account_id': {
      if (leaf.op === 'is') return t.account === leaf.value;
      if (leaf.op === 'in') return leaf.value.includes(t.account);
      return false;
    }
    case 'category_id': {
      if (leaf.op === 'is_null') return t.category == null;
      const c = t.category ?? '';
      if (leaf.op === 'is') return c === leaf.value;
      if (leaf.op === 'in') return c !== '' && leaf.value.includes(c);
      return false;
    }
    case 'counterparty_id': {
      if (leaf.op === 'is_null') return t.counterpartyId == null;
      return leaf.op === 'is' && t.counterpartyId === leaf.value;
    }
    case 'currency':
      return leaf.op === 'is' && (t.currency ?? '') === leaf.value;
    case 'date_dow':
      return leaf.op === 'in' && leaf.value.includes(dayOfWeek(t.date));
    case 'date_dom': {
      const d = dayOfMonth(t.date);
      if (leaf.op === 'eq') return d === leaf.value;
      if (leaf.op === 'gte') return d >= leaf.value;
      if (leaf.op === 'lte') return d <= leaf.value;
      return false;
    }
    case 'kind': {
      const k = kindOf(t);
      if (leaf.op === 'is') return k === leaf.value;
      if (leaf.op === 'in') return leaf.value.includes(k);
      return false;
    }
    case 'tag_id': {
      const tags = t.tags ?? [];
      if (leaf.op === 'has') return tags.includes(leaf.value);
      if (leaf.op === 'has_any') return leaf.value.some((id) => tags.includes(id));
      if (leaf.op === 'has_all') return leaf.value.every((id) => tags.includes(id));
      return false;
    }
    case 'note': {
      const n = t.note ?? '';
      const a = leaf.caseInsensitive === false ? n : n.toLowerCase();
      const b = leaf.caseInsensitive === false ? leaf.value : leaf.value.toLowerCase();
      return leaf.op === 'contains' && a.includes(b);
    }
  }
}

/** Evaluate a (possibly nested) condition against a transaction. */
export function evaluateCondition(t: Tx, cond: Condition): boolean {
  // The discriminator: combinators carry one of {all, any, not}; leaves carry {field}.
  if ('all' in cond) return cond.all.every((c) => evaluateCondition(t, c));
  if ('any' in cond) return cond.any.some((c) => evaluateCondition(t, c));
  if ('not' in cond) return !evaluateCondition(t, cond.not);
  return evaluateLeaf(t, cond);
}

// ---------------------------------------------------------------------------
// Action merging. The plan (§5) commits to:
//   - set_* actions: later writer wins; the losing rule still goes into
//     appliedRuleIds for traceability.
//   - tags: accumulate (add/remove sets union across rules).
//   - mark_reviewed: any matching rule sets it true; cannot be cleared.
//   - split: mutually exclusive — first matching split action wins, later
//     splits are ignored but their rule id is still recorded.
// Within a single rule, actions also apply in order; the same merge semantics
// hold (so a rule that sets category twice keeps the second value).
// ---------------------------------------------------------------------------

function applyAction(patch: RulePatch, a: Action): void {
  switch (a.type) {
    case 'set_category':     patch.categoryId = a.categoryId; return;
    case 'set_counterparty': patch.counterpartyId = a.counterpartyId; return;
    case 'set_merchant':     patch.merchant = a.merchant; return;
    case 'set_note':         patch.note = a.note; return;
    case 'set_kind':         patch.kind = a.kind; return;
    case 'add_tag': {
      patch.tagIdsAdd = patch.tagIdsAdd ?? [];
      if (!patch.tagIdsAdd.includes(a.tagId)) patch.tagIdsAdd.push(a.tagId);
      return;
    }
    case 'remove_tag': {
      patch.tagIdsRemove = patch.tagIdsRemove ?? [];
      if (!patch.tagIdsRemove.includes(a.tagId)) patch.tagIdsRemove.push(a.tagId);
      return;
    }
    case 'mark_reviewed':    patch.reviewed = true; return;
    case 'split': {
      // First split wins. Subsequent splits are dropped (their rule id is
      // still recorded by the outer apply loop — see applyRules below).
      if (patch.splits === undefined) patch.splits = a.splits.map((s) => ({ ...s }));
      return;
    }
  }
}

export interface ApplyOptions {
  /** Skip the engine entirely when the transaction was already touched by a
   *  rule. The infinite-loop guard for the auto-transfer case: a rule whose
   *  action generates a new transfer must not have rules re-fired on the
   *  generated rows. */
  skipIfRuleApplied?: boolean;
  /** Only run rules with runOnEdit=true. Used by the edit path; insert uses
   *  the default of false (all active rules run). */
  onEditOnly?: boolean;
}

/**
 * Run the (already-ordered) active rules against `t`. Returns a merged patch.
 *
 * The caller is responsible for passing `rules` in priority order — i.e. the
 * apply order: the lower-priority rule runs first, and a later rule's
 * `set_*` action wins. The engine itself only iterates.
 *
 * The returned patch's `appliedRuleIds` lists every rule that matched in the
 * order it fired, even if a later rule overrode its writes — that's the
 * audit trail. An empty `appliedRuleIds` means no rule matched.
 */
export function applyRules(t: Tx, rules: Rule[], opts: ApplyOptions = {}): RulePatch {
  const patch: RulePatch = { appliedRuleIds: [] };
  if (opts.skipIfRuleApplied && (t.appliedRuleIds?.length ?? 0) > 0) return patch;
  for (const rule of rules) {
    if (!rule.isActive) continue;
    if (opts.onEditOnly && !rule.runOnEdit) continue;
    if (!evaluateCondition(t, rule.condition)) continue;
    patch.appliedRuleIds.push(rule.id);
    for (const action of rule.actions) applyAction(patch, action);
  }
  return patch;
}

// Re-export the action data type so engine consumers can import from one place.
export type { SplitTemplate };
