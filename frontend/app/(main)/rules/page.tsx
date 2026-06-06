'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { EmptyState } from '@/components/empty-state';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { describeActions, describeCondition } from '@/lib/rules/describe';
import { applyRules } from '@/lib/rules/engine';
import { RuleBuilderSheet } from '@/components/rule-builder-sheet';
import { cn } from '@/lib/utils';
import type { Rule } from '@/lib/rules/types';

function relativeDays(iso: string | null): string | null {
  if (!iso) return null;
  const t = new Date(iso).getTime();
  if (!Number.isFinite(t)) return null;
  const days = Math.floor((Date.now() - t) / 86400000);
  if (days < 1) return 'today';
  if (days < 2) return 'yesterday';
  if (days < 30) return `${days} days ago`;
  const months = Math.round(days / 30);
  return months === 1 ? 'last month' : `${months} months ago`;
}

export default function RulesPage() {
  const { activeId, active } = useLedger();
  const rules = useFinanceStore((s) => s.rules);
  const txns = useFinanceStore((s) => s.transactions);
  const updateRule = useFinanceStore((s) => s.updateRule);
  const deleteRule = useFinanceStore((s) => s.deleteRule);
  const backfillRule = useFinanceStore((s) => s.backfillRule);
  const [openRule, setOpenRule] = useState<Rule | null>(null);
  const [builderRule, setBuilderRule] = useState<Rule | null>(null);
  const [builderOpen, setBuilderOpen] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState<Rule | null>(null);
  const [confirmBackfill, setConfirmBackfill] = useState<Rule | null>(null);

  const openNewBuilder = () => {
    setBuilderRule(null);
    setBuilderOpen(true);
  };
  const openEditBuilder = (r: Rule) => {
    setBuilderRule(r);
    setBuilderOpen(true);
    setOpenRule(null);
  };
  const closeBuilder = () => setBuilderOpen(false);

  const onToggle = (r: Rule) => {
    updateRule(r.id, { isActive: !r.isActive });
    toast.success(`Rule ${r.name ?? r.id} ${r.isActive ? 'disabled' : 'enabled'}`);
    setOpenRule(null);
  };

  const onDelete = (r: Rule) => {
    deleteRule(r.id);
    toast.success(`Rule ${r.name ?? r.id} deleted`);
    setConfirmDelete(null);
    setOpenRule(null);
  };

  // Client-side preview: run the rule against the projected confirmed
  // transactions in this ledger so the user knows what they're about to
  // touch BEFORE the server commits. Pure on the projected store.
  const previewBackfill = (r: Rule) => {
    const candidates = txns.filter((t) => (t.ledgerId ?? 'personal') === r.ledgerId && !t.pending);
    const matched: typeof txns = [];
    for (const t of candidates) {
      const patch = applyRules(t, [r]);
      if (patch.appliedRuleIds.includes(r.id)) matched.push(t);
    }
    return { matched, total: candidates.length };
  };

  const onBackfill = (r: Rule) => {
    backfillRule(r.id);
    toast.success(`Backfilling rule${r.name ? ` "${r.name}"` : ''}`, {
      description: 'Server is applying the rule across history.',
    });
    setConfirmBackfill(null);
    setOpenRule(null);
  };

  const ledgerRules = rules.filter((r) => r.ledgerId === activeId);
  // Per-rule "applied to N transactions" count from the projected store.
  const matchCountByRule = new Map<string, number>();
  for (const t of txns) {
    const ids = t.appliedRuleIds;
    if (!ids?.length) continue;
    for (const id of ids) matchCountByRule.set(id, (matchCountByRule.get(id) ?? 0) + 1);
  }

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Rules"
          trailing={
            <IconButton icon="plus" aria-label="New rule" variant="primary" onClick={openNewBuilder} />
          }
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="mb-4 flex items-center justify-between gap-3">
          <div className="text-muted-foreground text-xs leading-relaxed">
            Rules run automatically on every new transaction in <span className="text-foreground font-medium">{active.name}</span>.
            A matching rule can set the category, add a tag, rename the merchant, or split the row.
          </div>
          <Button onClick={openNewBuilder} size="sm" className="hidden shrink-0 md:flex">
            <Icon name="plus" size={14} />
            New rule
          </Button>
        </div>

        {ledgerRules.length === 0 ? (
          <EmptyState
            icon="sparkle"
            title="No rules yet"
            description="Rules categorise repeat merchants automatically. Tap “New rule” to set one up — start with the merchant you re-categorise most often."
            action={
              <Button onClick={openNewBuilder}>
                <Icon name="plus" size={14} />
                New rule
              </Button>
            }
          />
        ) : (
          <ul className="bg-card border-border divide-border divide-y rounded-xl border">
            {ledgerRules.map((r) => {
              const matchCount = matchCountByRule.get(r.id) ?? 0;
              const lastApplied = relativeDays(r.lastAppliedAt);
              return (
                <li key={r.id}>
                  <button
                    type="button"
                    onClick={() => setOpenRule(r)}
                    className="hover:bg-secondary/40 focus-ring flex w-full items-center gap-3 px-4 py-3 text-left outline-none"
                    aria-label={`Open rule ${r.name ?? r.id}`}
                  >
                    <span
                      className={cn(
                        'mt-0.5 size-1.5 shrink-0 rounded-full',
                        r.isActive ? 'bg-success' : 'bg-muted-foreground/40',
                      )}
                      aria-hidden
                    />
                    <div className="min-w-0 flex-1">
                      <div className="flex items-baseline gap-2">
                        <span className="truncate text-sm font-medium">
                          {r.name ?? <span className="text-muted-foreground italic">unnamed</span>}
                        </span>
                        {!r.isActive && (
                          <span className="text-muted-foreground text-[10px] uppercase tracking-wide">
                            disabled
                          </span>
                        )}
                      </div>
                      <div className="text-muted-foreground mt-0.5 truncate font-mono text-[11px]">
                        {describeCondition(r.condition)}
                      </div>
                      <div className="text-muted-foreground mt-0.5 truncate text-[11px]">
                        → {describeActions(r.actions)}
                      </div>
                    </div>
                    <div className="text-muted-foreground shrink-0 text-right font-mono text-[10px] tabular-nums">
                      {matchCount > 0 && <div>{matchCount} matched</div>}
                      {lastApplied && <div className="mt-0.5">{lastApplied}</div>}
                    </div>
                    <Icon name="chev" size={14} className="text-muted-foreground shrink-0" />
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <RuleDetailSheet
        rule={openRule}
        onClose={() => setOpenRule(null)}
        matchCountByRule={matchCountByRule}
        onEdit={openEditBuilder}
        onToggle={onToggle}
        onAskDelete={(r) => setConfirmDelete(r)}
        onAskBackfill={(r) => setConfirmBackfill(r)}
      />

      <RuleBuilderSheet rule={builderRule} open={builderOpen} onClose={closeBuilder} />

      <Dialog open={!!confirmBackfill} onOpenChange={(o) => !o && setConfirmBackfill(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Apply rule to existing transactions?</DialogTitle>
            <DialogDescription>
              This walks every confirmed transaction in this ledger and applies the rule&rsquo;s actions
              to those that match. Splits aren&rsquo;t backfilled in this pass; everything else does land.
            </DialogDescription>
          </DialogHeader>
          {confirmBackfill && (() => {
            const { matched, total } = previewBackfill(confirmBackfill);
            const samples = matched.slice(0, 5);
            return (
              <div className="text-sm">
                <div className="mb-2">
                  <span className="font-medium">{matched.length}</span> of <span className="font-medium">{total}</span>{' '}
                  confirmed transactions match.
                </div>
                {samples.length > 0 ? (
                  <ul className="bg-secondary text-muted-foreground space-y-0.5 rounded-md p-2 font-mono text-[11px]">
                    {samples.map((t) => (
                      <li key={t.id} className="truncate">
                        {t.date} · {t.merchant} · ${Math.abs(t.nativeAmount ?? t.amount).toFixed(2)}
                      </li>
                    ))}
                    {matched.length > samples.length && (
                      <li className="italic">+{matched.length - samples.length} more</li>
                    )}
                  </ul>
                ) : (
                  <div className="text-muted-foreground italic">Nothing to apply — no matches in history.</div>
                )}
              </div>
            );
          })()}
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={() => confirmBackfill && onBackfill(confirmBackfill)}>
              <Icon name="check" size={14} />
              Apply to existing
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!confirmDelete} onOpenChange={(o) => !o && setConfirmDelete(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete this rule?</DialogTitle>
            <DialogDescription>
              The rule won&rsquo;t fire on new transactions. Existing rows it already touched
              keep their values; the rule id stays in their <code>applied_rule_ids</code> for traceability.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button variant="destructive" onClick={() => confirmDelete && onDelete(confirmDelete)}>
              Delete rule
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}

function RuleDetailSheet({
  rule,
  onClose,
  matchCountByRule,
  onEdit,
  onToggle,
  onAskDelete,
  onAskBackfill,
}: {
  rule: Rule | null;
  onClose: () => void;
  matchCountByRule: Map<string, number>;
  onEdit: (r: Rule) => void;
  onToggle: (r: Rule) => void;
  onAskDelete: (r: Rule) => void;
  onAskBackfill: (r: Rule) => void;
}) {
  return (
    <Dialog open={!!rule} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="flex max-h-[85vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-md">
        <DialogHeader className="border-border shrink-0 border-b px-5 py-4">
          <DialogTitle className="font-serif text-xl italic">
            {rule?.name ?? 'Rule'}
          </DialogTitle>
          <DialogDescription className="sr-only">Rule detail</DialogDescription>
        </DialogHeader>
        {rule && (
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-4 text-sm">
            <div className="flex flex-wrap gap-2">
              <Button size="sm" onClick={() => onEdit(rule)}>
                <Icon name="edit" size={13} />Edit
              </Button>
              <Button size="sm" variant="outline" onClick={() => onToggle(rule)}>
                <Icon name={rule.isActive ? 'x' : 'check'} size={13} />
                {rule.isActive ? 'Disable' : 'Enable'}
              </Button>
              <Button size="sm" variant="outline" onClick={() => onAskBackfill(rule)}>
                <Icon name="sync" size={13} />Apply to existing
              </Button>
              <Button size="sm" variant="outline" onClick={() => onAskDelete(rule)} className="text-destructive">
                <Icon name="trash" size={13} />Delete
              </Button>
            </div>
            <DetailRow label="Status">
              <span className={cn('font-medium', rule.isActive ? 'text-success' : 'text-muted-foreground')}>
                {rule.isActive ? 'Active' : 'Disabled'}
              </span>
            </DetailRow>
            <DetailRow label="Priority">{rule.priority}</DetailRow>
            <DetailRow label="Re-runs on edit">{rule.runOnEdit ? 'Yes' : 'No'}</DetailRow>
            <DetailRow label="Applied to">
              {matchCountByRule.get(rule.id) ?? 0} transaction{(matchCountByRule.get(rule.id) ?? 0) === 1 ? '' : 's'}
            </DetailRow>
            <div>
              <div className="text-muted-foreground mb-1.5 font-mono text-[10px] uppercase tracking-wide">
                Condition
              </div>
              <pre className="bg-secondary rounded-md p-3 font-mono text-[11px] whitespace-pre-wrap">
                {describeCondition(rule.condition)}
              </pre>
            </div>
            <div>
              <div className="text-muted-foreground mb-1.5 font-mono text-[10px] uppercase tracking-wide">
                Actions
              </div>
              <ol className="space-y-1 text-[12px]">
                {rule.actions.length === 0 ? (
                  <li className="text-muted-foreground italic">(no actions)</li>
                ) : (
                  rule.actions.map((a, i) => (
                    <li key={i} className="bg-secondary rounded px-2 py-1 font-mono text-[11px]">
                      {i + 1}. {JSON.stringify(a)}
                    </li>
                  ))
                )}
              </ol>
            </div>
            <DetailRow label="Last backfilled">
              {relativeDays(rule.lastAppliedAt) ?? '—'}
            </DetailRow>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function DetailRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="text-muted-foreground text-[11px]">{label}</span>
      <span className="text-foreground text-[13px]">{children}</span>
    </div>
  );
}
