'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Icon } from '@/components/primitives';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { applyRules, evaluateCondition } from '@/lib/rules/engine';
import { describeCondition, describeActions } from '@/lib/rules/describe';
import { useDescribeDict } from '@/lib/rules/use-describe-dict';
import { cn } from '@/lib/utils';
import { categoryPath } from '@/lib/db/domain/categories/queries';
import type { Action, Condition, Leaf, Rule, TxKind } from '@/lib/rules/types';
import type { Tx } from '@/lib/store';

// ---------------------------------------------------------------------------
// Draft model — UI-friendly flat shape. The builder doesn't expose nested
// (all-inside-any, NOT) trees in this version; power users hand-edit the
// JSON. The flat form covers the 80% case (Lunch Money / Tiller's AutoCat
// pattern: glob ANDed leaves).
// ---------------------------------------------------------------------------

interface Draft {
  name: string;
  priority: number;
  isActive: boolean;
  runOnEdit: boolean;
  combinator: 'all' | 'any';
  leaves: Leaf[];
  actions: Action[];
}

const KIND_VALUES: TxKind[] = ['expense', 'income', 'transfer', 'refund', 'adjustment'];

const FIELD_VALUES: Leaf['field'][] = [
  'merchant',
  'amount',
  'account_id',
  'category_id',
  'counterparty_id',
  'currency',
  'date_dow',
  'date_dom',
  'kind',
  'tag_id',
  'note',
];

const ACTION_VALUES: Action['type'][] = [
  'set_category',
  'add_tag',
  'remove_tag',
  'set_counterparty',
  'set_merchant',
  'set_note',
  'set_kind',
  'mark_reviewed',
];

const WEEKDAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const;

function defaultLeaf(field: Leaf['field']): Leaf {
  switch (field) {
    case 'merchant': return { field, op: 'contains', value: '' };
    case 'amount': return { field, op: 'lt', value: 10 };
    case 'account_id': return { field, op: 'is', value: '' };
    case 'category_id': return { field, op: 'is', value: '' };
    case 'counterparty_id': return { field, op: 'is', value: '' };
    case 'currency': return { field, op: 'is', value: 'USD' };
    case 'date_dow': return { field, op: 'in', value: [] };
    case 'date_dom': return { field, op: 'eq', value: 1 };
    case 'kind': return { field, op: 'is', value: 'expense' };
    case 'tag_id': return { field, op: 'has', value: '' };
    case 'note': return { field, op: 'contains', value: '' };
  }
}

function defaultAction(type: Action['type']): Action {
  switch (type) {
    case 'set_category': return { type, categoryId: null };
    case 'add_tag': return { type, tagId: '' };
    case 'remove_tag': return { type, tagId: '' };
    case 'set_counterparty': return { type, counterpartyId: null };
    case 'set_merchant': return { type, merchant: '' };
    case 'set_note': return { type, note: '' };
    case 'set_kind': return { type, kind: 'expense' };
    case 'mark_reviewed': return { type };
    case 'split': return { type, splits: [] };
  }
}

/** Build the JSON Condition from the flat draft. */
function buildCondition(draft: Draft): Condition {
  return draft.combinator === 'all' ? { all: draft.leaves } : { any: draft.leaves };
}

/** Decompose a Condition back into the flat draft for editing. Nested
 *  trees collapse to a single "(complex — view-only)" leaf so the user can
 *  see the rule exists; saving overwrites their flat draft. */
function decomposeCondition(cond: Condition): { combinator: 'all' | 'any'; leaves: Leaf[] } {
  if ('all' in cond && cond.all.every((c) => 'field' in c)) {
    return { combinator: 'all', leaves: cond.all as Leaf[] };
  }
  if ('any' in cond && cond.any.every((c) => 'field' in c)) {
    return { combinator: 'any', leaves: cond.any as Leaf[] };
  }
  // Non-flat tree — fall back to a single placeholder leaf so saving doesn't
  // silently corrupt the rule. The user can drop in a fresh condition.
  return { combinator: 'all', leaves: [defaultLeaf('merchant')] };
}

/** Optional seed for a fresh-rule draft. Used by the "always categorize X as
 *  Y?" inline prompt to drop the user into the builder with the merchant +
 *  category already filled in. Ignored when an existing rule is loaded. */
export interface RulePrefill {
  name?: string;
  leaves?: Leaf[];
  actions?: Action[];
}

function makeDraft(rule: Rule | null, prefill?: RulePrefill): Draft {
  if (!rule) {
    return {
      name: prefill?.name ?? '',
      priority: 100,
      isActive: true,
      runOnEdit: false,
      combinator: 'all',
      leaves: prefill?.leaves ?? [defaultLeaf('merchant')],
      actions: prefill?.actions ?? [defaultAction('set_category')],
    };
  }
  const { combinator, leaves } = decomposeCondition(rule.condition);
  return {
    name: rule.name ?? '',
    priority: rule.priority,
    isActive: rule.isActive,
    runOnEdit: rule.runOnEdit,
    combinator,
    leaves,
    actions: rule.actions,
  };
}

// ---------------------------------------------------------------------------

export function RuleBuilderSheet({
  rule,
  open,
  onClose,
  prefill,
}: {
  rule: Rule | null;
  open: boolean;
  onClose: () => void;
  /** Initial draft seed when creating a new rule; ignored for edits. */
  prefill?: RulePrefill;
}) {
  const { activeId } = useLedger();
  const t = useTranslations('ruleBuilder');
  const tCommon = useTranslations('common');
  const describeDict = useDescribeDict();
  const categories = useFinanceStore((s) => s.categories);
  const accounts = useFinanceStore((s) => s.accounts);
  const counterparties = useFinanceStore((s) => s.counterparties);
  const tags = useFinanceStore((s) => s.tags);
  const transactions = useFinanceStore((s) => s.transactions);
  const createRule = useFinanceStore((s) => s.createRule);
  const updateRule = useFinanceStore((s) => s.updateRule);

  const [draft, setDraft] = useState<Draft>(() => makeDraft(rule, prefill));

  // Reset the draft whenever the sheet (re)opens for a different rule / new
  // prefill. The key is "rule.id || prefill-fingerprint" so two distinct
  // prefills produce distinct drafts even when both are new rules.
  const prefillKey = prefill
    ? JSON.stringify({ n: prefill.name, l: prefill.leaves, a: prefill.actions })
    : '';
  const draftKey = `${rule?.id ?? ''}|${prefillKey}`;
  const [lastDraftKey, setLastDraftKey] = useState<string>(draftKey);
  if (open && lastDraftKey !== draftKey) {
    setDraft(makeDraft(rule, prefill));
    setLastDraftKey(draftKey);
  }

  // Labels render as `Parent › Child › Leaf` for unambiguous depth-3
  // picks (CATEGORIES_LEVEL3_PLAN §5.1). Sorted by path so siblings cluster.
  const ledgerCategoriesRaw = categories.filter((c) => c.ledgerId === activeId);
  const ledgerCatByIdMap = new Map(ledgerCategoriesRaw.map((c) => [c.id, c]));
  const ledgerCategories = ledgerCategoriesRaw
    .map((c) => ({ id: c.id, name: categoryPath(c, ledgerCatByIdMap) }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const ledgerAccounts = accounts.filter((a) => a.ledgerId === activeId);
  const ledgerCounterparties = counterparties.filter((c) => c.ledgerId === activeId);
  const ledgerTags = tags.filter((t) => t.ledgerId === activeId);

  // Live preview — runs the draft against the last 100 confirmed transactions
  // in the active ledger. Counts matches; surfaces the first three so the
  // user can sanity-check before saving.
  const condition = buildCondition(draft);
  const preview = useMemo(() => {
    const recent = transactions
      .filter((t) => (t.ledgerId ?? 'personal') === activeId && !t.pending)
      .slice(0, 100);
    const draftRule: Rule = {
      id: 'preview',
      ledgerId: activeId,
      name: null,
      priority: draft.priority,
      condition,
      actions: draft.actions,
      isActive: true,
      runOnEdit: false,
      lastAppliedAt: null,
    };
    const matches: Tx[] = [];
    for (const t of recent) {
      if (evaluateCondition(t, condition)) matches.push(t);
    }
    const samplePatch = matches[0] ? applyRules(matches[0], [draftRule]) : null;
    return { matchCount: matches.length, total: recent.length, samples: matches.slice(0, 3), samplePatch };
  }, [transactions, activeId, condition, draft.actions, draft.priority]);

  const save = () => {
    if (!draft.leaves.length) {
      toast.error(t('errors.noConditions'));
      return;
    }
    if (!draft.actions.length) {
      toast.error(t('errors.noActions'));
      return;
    }
    if (rule) {
      updateRule(rule.id, {
        name: draft.name.trim() || null,
        priority: draft.priority,
        condition,
        actions: draft.actions,
        isActive: draft.isActive,
        runOnEdit: draft.runOnEdit,
      });
      toast.success(t('toasts.updated', { name: draft.name.trim() || rule.id }));
    } else {
      const id = createRule({
        name: draft.name.trim() || null,
        priority: draft.priority,
        condition,
        actions: draft.actions,
        isActive: draft.isActive,
        runOnEdit: draft.runOnEdit,
        ledgerId: activeId,
      });
      toast.success(t('toasts.created', { name: draft.name.trim() || id }));
    }
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="flex max-h-[88vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-lg">
        <DialogHeader className="border-border shrink-0 border-b px-5 py-4">
          <DialogTitle className="font-serif text-xl italic">
            {rule ? t('editTitle') : t('newTitle')}
          </DialogTitle>
          <DialogDescription className="sr-only">
            {t('description')}
          </DialogDescription>
        </DialogHeader>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto px-5 py-4">
          {/* Name + priority + flags */}
          <section className="space-y-2.5">
            <div className="flex flex-col gap-1">
              <Label htmlFor="rule-name" className="text-muted-foreground text-[11px]">{t('fieldLabels.nameOptional')}</Label>
              <Input
                id="rule-name"
                value={draft.name}
                onChange={(e) => setDraft((d) => ({ ...d, name: e.target.value }))}
                placeholder={t('fieldLabels.namePlaceholder')}
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1">
                <Label htmlFor="rule-priority" className="text-muted-foreground text-[11px]">{t('fieldLabels.priority')}</Label>
                <Input
                  id="rule-priority"
                  type="number"
                  value={draft.priority}
                  onChange={(e) => setDraft((d) => ({ ...d, priority: Number(e.target.value) || 0 }))}
                />
              </div>
              <div className="flex flex-col gap-2 pt-5">
                <label className="flex items-center gap-2 text-[12px]">
                  <input
                    type="checkbox"
                    checked={draft.isActive}
                    onChange={(e) => setDraft((d) => ({ ...d, isActive: e.target.checked }))}
                  />
                  {t('fieldLabels.active')}
                </label>
                <label className="flex items-center gap-2 text-[12px]" title={t('fieldLabels.rerunOnEditTitle')}>
                  <input
                    type="checkbox"
                    checked={draft.runOnEdit}
                    onChange={(e) => setDraft((d) => ({ ...d, runOnEdit: e.target.checked }))}
                  />
                  {t('fieldLabels.rerunOnEdit')}
                </label>
              </div>
            </div>
          </section>

          {/* Condition builder */}
          <section className="space-y-2">
            <div className="flex items-center justify-between">
              <Label className="text-muted-foreground text-[11px]">{t('fieldLabels.when')}</Label>
              <Select value={draft.combinator} onValueChange={(v) => setDraft((d) => ({ ...d, combinator: v as 'all' | 'any' }))}>
                <SelectTrigger size="sm" className="h-7 w-[120px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t('fieldLabels.allOfThese')}</SelectItem>
                  <SelectItem value="any">{t('fieldLabels.anyOfThese')}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <ol className="space-y-2">
              {draft.leaves.map((leaf, i) => (
                <li key={i}>
                  <LeafEditor
                    leaf={leaf}
                    accounts={ledgerAccounts}
                    categories={ledgerCategories}
                    counterparties={ledgerCounterparties}
                    tags={ledgerTags}
                    onChange={(next) =>
                      setDraft((d) => ({ ...d, leaves: d.leaves.map((l, j) => (j === i ? next : l)) }))
                    }
                    onRemove={
                      draft.leaves.length > 1
                        ? () =>
                            setDraft((d) => ({ ...d, leaves: d.leaves.filter((_, j) => j !== i) }))
                        : undefined
                    }
                  />
                </li>
              ))}
            </ol>
            <button
              type="button"
              onClick={() =>
                setDraft((d) => ({ ...d, leaves: [...d.leaves, defaultLeaf('merchant')] }))
              }
              className="text-primary text-[12px] underline-offset-2 hover:underline"
            >
              {t('fieldLabels.addCondition')}
            </button>
          </section>

          {/* Action picker */}
          <section className="space-y-2">
            <Label className="text-muted-foreground text-[11px]">{t('fieldLabels.then')}</Label>
            <ol className="space-y-2">
              {draft.actions.map((action, i) => (
                <li key={i}>
                  <ActionEditor
                    action={action}
                    categories={ledgerCategories}
                    counterparties={ledgerCounterparties}
                    tags={ledgerTags}
                    onChange={(next) =>
                      setDraft((d) => ({ ...d, actions: d.actions.map((a, j) => (j === i ? next : a)) }))
                    }
                    onRemove={
                      draft.actions.length > 1
                        ? () =>
                            setDraft((d) => ({ ...d, actions: d.actions.filter((_, j) => j !== i) }))
                        : undefined
                    }
                  />
                </li>
              ))}
            </ol>
            <button
              type="button"
              onClick={() =>
                setDraft((d) => ({ ...d, actions: [...d.actions, defaultAction('set_category')] }))
              }
              className="text-primary text-[12px] underline-offset-2 hover:underline"
            >
              {t('fieldLabels.addAction')}
            </button>
          </section>

          {/* Test panel */}
          <section className="bg-secondary space-y-2 rounded-xl p-3">
            <div className="text-muted-foreground font-mono text-[10px] uppercase tracking-wide">
              {t('test.header', { total: preview.total })}
            </div>
            <div className="text-foreground text-[13px]">
              {t('test.matches', { count: preview.matchCount })}
            </div>
            {preview.samples.length > 0 ? (
              <ul className="text-muted-foreground space-y-0.5 font-mono text-[10px]">
                {preview.samples.map((sample) => (
                  <li key={sample.id} className="truncate">
                    {sample.date} · {sample.merchant} · ${Math.abs(sample.nativeAmount ?? sample.amount).toFixed(2)}
                  </li>
                ))}
                {preview.matchCount > preview.samples.length && (
                  <li className="text-muted-foreground italic">
                    {t('test.moreCount', { count: preview.matchCount - preview.samples.length })}
                  </li>
                )}
              </ul>
            ) : (
              <div className="text-muted-foreground text-[11px] italic">{t('test.noMatchesYet')}</div>
            )}
            <div className="border-border mt-2 border-t pt-2">
              <div className="text-muted-foreground font-mono text-[10px] uppercase tracking-wide">
                {t('test.summary')}
              </div>
              <div className="text-foreground mt-1 font-mono text-[11px]">
                {describeCondition(condition, describeDict)} → {describeActions(draft.actions, describeDict)}
              </div>
            </div>
          </section>
        </div>

        <div className="border-border bg-card shrink-0 border-t px-5 py-3">
          <div className="flex items-center justify-end gap-2">
            <Button variant="outline" onClick={onClose}>
              {tCommon('cancel')}
            </Button>
            <Button onClick={save}>
              <Icon name="check" size={14} />
              {rule ? t('footer.saveChanges') : t('footer.createRule')}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Leaf editor — picks the field, op, and value type-specific input.
// ---------------------------------------------------------------------------

interface LeafEditorProps {
  leaf: Leaf;
  accounts: { id: string; name: string }[];
  categories: { id: string; name: string }[];
  counterparties: { id: string; name: string }[];
  tags: { id: string; name: string }[];
  onChange: (leaf: Leaf) => void;
  onRemove?: () => void;
}

function LeafEditor({ leaf, accounts, categories, counterparties, tags, onChange, onRemove }: LeafEditorProps) {
  const t = useTranslations('ruleBuilder');
  return (
    <div className="bg-card border-border space-y-2 rounded-lg border p-2.5">
      <div className="flex items-center gap-2">
        <Select value={leaf.field} onValueChange={(v) => onChange(defaultLeaf(v as Leaf['field']))}>
          <SelectTrigger size="sm" className="h-7 flex-1">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {FIELD_VALUES.map((v) => (
              <SelectItem key={v} value={v}>{t(`fields.${v}`)}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        {onRemove && (
          <button
            type="button"
            onClick={onRemove}
            aria-label={t('fieldLabels.removeConditionAria')}
            className="text-muted-foreground hover:text-foreground rounded p-1"
          >
            <Icon name="x" size={14} />
          </button>
        )}
      </div>
      <LeafBody leaf={leaf} onChange={onChange}
        accounts={accounts} categories={categories} counterparties={counterparties} tags={tags} />
    </div>
  );
}

function LeafBody({ leaf, onChange, accounts, categories, counterparties, tags }: LeafEditorProps) {
  const t = useTranslations('ruleBuilder');
  const inputClass = 'h-8 text-[12px]';

  if (leaf.field === 'merchant') {
    return (
      <div className="grid grid-cols-[100px_1fr] gap-2">
        <Select value={leaf.op} onValueChange={(v) => onChange({ ...leaf, op: v as Leaf['op'] } as Leaf)}>
          <SelectTrigger size="sm" className="h-8 text-[12px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="is">{t('operators.is')}</SelectItem>
            <SelectItem value="contains">{t('operators.contains')}</SelectItem>
            <SelectItem value="startsWith">{t('operators.startsWith')}</SelectItem>
          </SelectContent>
        </Select>
        <Input
          value={leaf.value}
          onChange={(e) => onChange({ ...leaf, value: e.target.value } as Leaf)}
          className={inputClass}
          placeholder={t('placeholders.text')}
        />
      </div>
    );
  }
  if (leaf.field === 'amount') {
    if (leaf.op === 'between') {
      const [lo, hi] = Array.isArray(leaf.value) ? leaf.value : [0, 0];
      return (
        <div className="grid grid-cols-[100px_1fr_1fr] gap-2">
          <Select value="between" onValueChange={(v) => onChange({ ...leaf, op: v as Leaf['op'] } as Leaf)}>
            <SelectTrigger size="sm" className="h-8 text-[12px]"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="gt">&gt;</SelectItem>
              <SelectItem value="gte">≥</SelectItem>
              <SelectItem value="lt">&lt;</SelectItem>
              <SelectItem value="lte">≤</SelectItem>
              <SelectItem value="eq">=</SelectItem>
              <SelectItem value="between">{t('operators.between')}</SelectItem>
            </SelectContent>
          </Select>
          <Input type="number" value={lo} className={inputClass}
            onChange={(e) => onChange({ ...leaf, value: [Number(e.target.value) || 0, hi] } as Leaf)} />
          <Input type="number" value={hi} className={inputClass}
            onChange={(e) => onChange({ ...leaf, value: [lo, Number(e.target.value) || 0] } as Leaf)} />
        </div>
      );
    }
    return (
      <div className="grid grid-cols-[100px_1fr] gap-2">
        <Select value={leaf.op} onValueChange={(v) => {
          if (v === 'between') {
            onChange({ field: 'amount', op: 'between', value: [0, 0] });
          } else {
            const cur = Array.isArray(leaf.value) ? leaf.value[0] : leaf.value;
            onChange({ field: 'amount', op: v as 'gt' | 'gte' | 'lt' | 'lte' | 'eq', value: Number(cur) || 0 });
          }
        }}>
          <SelectTrigger size="sm" className="h-8 text-[12px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="gt">&gt;</SelectItem>
            <SelectItem value="gte">≥</SelectItem>
            <SelectItem value="lt">&lt;</SelectItem>
            <SelectItem value="lte">≤</SelectItem>
            <SelectItem value="eq">=</SelectItem>
            <SelectItem value="between">{t('operators.between')}</SelectItem>
          </SelectContent>
        </Select>
        <Input type="number" value={Number(leaf.value)} className={inputClass}
          onChange={(e) => onChange({ ...leaf, value: Number(e.target.value) || 0 } as Leaf)} />
      </div>
    );
  }
  if (leaf.field === 'account_id') {
    return (
      <RefPicker labelKey="account" value={String(leaf.value)} options={accounts}
        onChange={(v) => onChange({ field: 'account_id', op: 'is', value: v })} />
    );
  }
  if (leaf.field === 'category_id') {
    return (
      <div className="grid grid-cols-[100px_1fr] gap-2">
        <Select value={leaf.op as string} onValueChange={(v) => {
          if (v === 'is_null') onChange({ field: 'category_id', op: 'is_null' });
          else onChange({ field: 'category_id', op: 'is', value: '' });
        }}>
          <SelectTrigger size="sm" className="h-8 text-[12px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="is">{t('operators.is')}</SelectItem>
            <SelectItem value="is_null">{t('operators.isNull')}</SelectItem>
          </SelectContent>
        </Select>
        {leaf.op !== 'is_null' && (
          <RefPicker labelKey="category" value={String(leaf.value ?? '')} options={categories}
            onChange={(v) => onChange({ field: 'category_id', op: 'is', value: v })} />
        )}
      </div>
    );
  }
  if (leaf.field === 'counterparty_id') {
    return (
      <div className="grid grid-cols-[100px_1fr] gap-2">
        <Select value={leaf.op as string} onValueChange={(v) => {
          if (v === 'is_null') onChange({ field: 'counterparty_id', op: 'is_null' });
          else onChange({ field: 'counterparty_id', op: 'is', value: '' });
        }}>
          <SelectTrigger size="sm" className="h-8 text-[12px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="is">{t('operators.is')}</SelectItem>
            <SelectItem value="is_null">{t('operators.isNull')}</SelectItem>
          </SelectContent>
        </Select>
        {leaf.op !== 'is_null' && (
          <RefPicker labelKey="counterparty" value={String(leaf.value ?? '')} options={counterparties}
            onChange={(v) => onChange({ field: 'counterparty_id', op: 'is', value: v })} />
        )}
      </div>
    );
  }
  if (leaf.field === 'currency') {
    return (
      <Input value={String(leaf.value)} className={inputClass}
        onChange={(e) => onChange({ ...leaf, value: e.target.value.toUpperCase() } as Leaf)} placeholder={t('placeholders.currency')} />
    );
  }
  if (leaf.field === 'date_dow') {
    const selected = Array.isArray(leaf.value) ? leaf.value : [];
    return (
      <div className="flex flex-wrap gap-1">
        {WEEKDAY_KEYS.map((key, i) => {
          const on = selected.includes(i);
          return (
            <button
              key={i}
              type="button"
              onClick={() => {
                const next = on ? selected.filter((x) => x !== i) : [...selected, i].sort();
                onChange({ field: 'date_dow', op: 'in', value: next });
              }}
              className={cn(
                'rounded px-2 py-0.5 text-[11px]',
                on ? 'bg-primary text-primary-foreground' : 'bg-card border-border border',
              )}
            >
              {t(`weekdays.${key}`)}
            </button>
          );
        })}
      </div>
    );
  }
  if (leaf.field === 'date_dom') {
    return (
      <div className="grid grid-cols-[100px_1fr] gap-2">
        <Select value={leaf.op} onValueChange={(v) => onChange({ ...leaf, op: v as 'eq' | 'gte' | 'lte' })}>
          <SelectTrigger size="sm" className="h-8 text-[12px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="eq">=</SelectItem>
            <SelectItem value="gte">≥</SelectItem>
            <SelectItem value="lte">≤</SelectItem>
          </SelectContent>
        </Select>
        <Input type="number" min={1} max={31} value={Number(leaf.value)} className={inputClass}
          onChange={(e) => onChange({ ...leaf, value: Math.max(1, Math.min(31, Number(e.target.value) || 1)) })} />
      </div>
    );
  }
  if (leaf.field === 'kind') {
    return (
      <Select value={String(leaf.value)} onValueChange={(v) => onChange({ field: 'kind', op: 'is', value: v as TxKind })}>
        <SelectTrigger size="sm" className="h-8 text-[12px]"><SelectValue /></SelectTrigger>
        <SelectContent>
          {KIND_VALUES.map((k) => <SelectItem key={k} value={k}>{t(`kinds.${k}`)}</SelectItem>)}
        </SelectContent>
      </Select>
    );
  }
  if (leaf.field === 'tag_id') {
    return (
      <RefPicker labelKey="tag" value={String(leaf.value)} options={tags}
        onChange={(v) => onChange({ field: 'tag_id', op: 'has', value: v })} />
    );
  }
  if (leaf.field === 'note') {
    return (
      <Input value={String(leaf.value)} className={inputClass}
        onChange={(e) => onChange({ field: 'note', op: 'contains', value: e.target.value })} placeholder={t('placeholders.noteText')} />
    );
  }
  return null;
}

function RefPicker({
  labelKey, value, options, onChange,
}: {
  labelKey: 'account' | 'category' | 'counterparty' | 'tag';
  value: string;
  options: { id: string; name: string }[];
  onChange: (v: string) => void;
}) {
  const t = useTranslations('ruleBuilder');
  const labelText = t(`refLabel.${labelKey}`);
  return (
    <Select value={value || undefined} onValueChange={onChange}>
      <SelectTrigger size="sm" className="h-8 text-[12px]">
        <SelectValue placeholder={t('placeholders.pickA', { label: labelText })} />
      </SelectTrigger>
      <SelectContent>
        {options.map((o) => (
          <SelectItem key={o.id} value={o.id}>{o.name}</SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

// ---------------------------------------------------------------------------
// Action editor.
// ---------------------------------------------------------------------------

interface ActionEditorProps {
  action: Action;
  categories: { id: string; name: string }[];
  counterparties: { id: string; name: string }[];
  tags: { id: string; name: string }[];
  onChange: (action: Action) => void;
  onRemove?: () => void;
}

function ActionEditor({ action, categories, counterparties, tags, onChange, onRemove }: ActionEditorProps) {
  const t = useTranslations('ruleBuilder');
  return (
    <div className="bg-card border-border space-y-2 rounded-lg border p-2.5">
      <div className="flex items-center gap-2">
        <Select value={action.type} onValueChange={(v) => onChange(defaultAction(v as Action['type']))}>
          <SelectTrigger size="sm" className="h-7 flex-1">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {ACTION_VALUES.map((v) => (
              <SelectItem key={v} value={v}>{t(`actions.${v}`)}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        {onRemove && (
          <button
            type="button"
            onClick={onRemove}
            aria-label={t('fieldLabels.removeActionAria')}
            className="text-muted-foreground hover:text-foreground rounded p-1"
          >
            <Icon name="x" size={14} />
          </button>
        )}
      </div>
      <ActionBody action={action} onChange={onChange} categories={categories} counterparties={counterparties} tags={tags} />
    </div>
  );
}

function ActionBody({ action, onChange, categories, counterparties, tags }: ActionEditorProps) {
  const t = useTranslations('ruleBuilder');
  const inputClass = 'h-8 text-[12px]';
  switch (action.type) {
    case 'set_category':
      return (
        <RefPicker labelKey="category" value={action.categoryId ?? ''} options={categories}
          onChange={(v) => onChange({ type: 'set_category', categoryId: v })} />
      );
    case 'set_counterparty':
      return (
        <RefPicker labelKey="counterparty" value={action.counterpartyId ?? ''} options={counterparties}
          onChange={(v) => onChange({ type: 'set_counterparty', counterpartyId: v })} />
      );
    case 'set_merchant':
      return (
        <Input value={action.merchant} className={inputClass}
          onChange={(e) => onChange({ type: 'set_merchant', merchant: e.target.value })} placeholder={t('placeholders.canonicalName')} />
      );
    case 'set_note':
      return (
        <Input value={action.note} className={inputClass}
          onChange={(e) => onChange({ type: 'set_note', note: e.target.value })} placeholder={t('placeholders.noteContent')} />
      );
    case 'set_kind':
      return (
        <Select value={action.kind} onValueChange={(v) => onChange({ type: 'set_kind', kind: v as TxKind })}>
          <SelectTrigger size="sm" className="h-8 text-[12px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            {KIND_VALUES.map((k) => <SelectItem key={k} value={k}>{t(`kinds.${k}`)}</SelectItem>)}
          </SelectContent>
        </Select>
      );
    case 'add_tag':
      return (
        <RefPicker labelKey="tag" value={action.tagId} options={tags}
          onChange={(v) => onChange({ type: 'add_tag', tagId: v })} />
      );
    case 'remove_tag':
      return (
        <RefPicker labelKey="tag" value={action.tagId} options={tags}
          onChange={(v) => onChange({ type: 'remove_tag', tagId: v })} />
      );
    case 'mark_reviewed':
      return <div className="text-muted-foreground text-[11px]">{t('actionHints.markReviewed')}</div>;
    case 'split':
      return <div className="text-muted-foreground text-[11px] italic">{t('actionHints.split')}</div>;
  }
}
