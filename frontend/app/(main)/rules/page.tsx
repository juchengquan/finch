'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { EmptyState } from '@/components/empty-state';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { describeActions, describeCondition } from '@/lib/rules/describe';
import { useDescribeDict } from '@/lib/rules/use-describe-dict';
import { applyRules } from '@/lib/rules/engine';
import { RuleBuilderSheet } from '@/components/rule-builder-sheet';
import { cn } from '@/lib/utils';
import type { Rule } from '@/lib/rules/types';

function useRelativeDays(): (iso: string | null) => string | null {
  const t = useTranslations('rules.relative');
  return (iso: string | null): string | null => {
    if (!iso) return null;
    const ts = new Date(iso).getTime();
    if (!Number.isFinite(ts)) return null;
    const days = Math.floor((Date.now() - ts) / 86400000);
    if (days < 1) return t('today');
    if (days < 2) return t('yesterday');
    if (days < 30) return t('daysAgo', { count: days });
    const months = Math.round(days / 30);
    return months === 1 ? t('lastMonth') : t('monthsAgo', { count: months });
  };
}

export default function RulesPage() {
  const { activeId, active } = useLedger();
  const t = useTranslations('rules');
  const tCommon = useTranslations('common');
  const relativeDays = useRelativeDays();
  const describeDict = useDescribeDict();
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
    const name = r.name ?? r.id;
    toast.success(r.isActive ? t('toasts.disabled', { name }) : t('toasts.enabled', { name }));
    setOpenRule(null);
  };

  const onDelete = (r: Rule) => {
    deleteRule(r.id);
    toast.success(t('toasts.deleted', { name: r.name ?? r.id }));
    setConfirmDelete(null);
    setOpenRule(null);
  };

  const previewBackfill = (r: Rule) => {
    const candidates = txns.filter((tx) => (tx.ledgerId ?? 'personal') === r.ledgerId && !tx.pending);
    const matched: typeof txns = [];
    for (const tx of candidates) {
      const patch = applyRules(tx, [r]);
      if (patch.appliedRuleIds.includes(r.id)) matched.push(tx);
    }
    return { matched, total: candidates.length };
  };

  const onBackfill = (r: Rule) => {
    backfillRule(r.id);
    toast.success(r.name ? t('toasts.backfilling', { name: r.name }) : t('toasts.backfillingUnnamed'), {
      description: t('toasts.backfillingDescription'),
    });
    setConfirmBackfill(null);
    setOpenRule(null);
  };

  const ledgerRules = rules.filter((r) => r.ledgerId === activeId);
  const matchCountByRule = new Map<string, number>();
  for (const tx of txns) {
    const ids = tx.appliedRuleIds;
    if (!ids?.length) continue;
    for (const id of ids) matchCountByRule.set(id, (matchCountByRule.get(id) ?? 0) + 1);
  }

  return (
    <MobilePage
      header={
        <ScreenHeader
          title={t('title')}
          trailing={
            <IconButton icon="plus" aria-label={t('newAria')} variant="primary" onClick={openNewBuilder} />
          }
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="mb-4 flex items-center justify-between gap-3">
          <div className="text-muted-foreground text-xs leading-relaxed">
            {t.rich('intro', {
              ledger: () => <span className="text-foreground font-medium">{active.name}</span>,
            })}
          </div>
          <Button onClick={openNewBuilder} size="sm" className="hidden shrink-0 md:flex">
            <Icon name="plus" size={14} />
            {t('newRule')}
          </Button>
        </div>

        {ledgerRules.length === 0 ? (
          <EmptyState
            icon="sparkle"
            title={t('empty.title')}
            description={t('empty.description')}
            action={
              <Button onClick={openNewBuilder}>
                <Icon name="plus" size={14} />
                {t('newRule')}
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
                    aria-label={t('row.openAria', { name: r.name ?? r.id })}
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
                          {r.name ?? <span className="text-muted-foreground italic">{t('row.unnamed')}</span>}
                        </span>
                        {!r.isActive && (
                          <span className="text-muted-foreground text-[10px] uppercase tracking-wide">
                            {t('row.disabled')}
                          </span>
                        )}
                      </div>
                      <div className="text-muted-foreground mt-0.5 truncate font-mono text-[11px]">
                        {describeCondition(r.condition, describeDict)}
                      </div>
                      <div className="text-muted-foreground mt-0.5 truncate text-[11px]">
                        → {describeActions(r.actions, describeDict)}
                      </div>
                    </div>
                    <div className="text-muted-foreground shrink-0 text-right font-mono text-[10px] tabular-nums">
                      {matchCount > 0 && <div>{t('row.matched', { count: matchCount })}</div>}
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
        relativeDays={relativeDays}
        describeDict={describeDict}
      />

      <RuleBuilderSheet rule={builderRule} open={builderOpen} onClose={closeBuilder} />

      <Dialog open={!!confirmBackfill} onOpenChange={(o) => !o && setConfirmBackfill(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('backfillDialog.title')}</DialogTitle>
            <DialogDescription>{t('backfillDialog.description')}</DialogDescription>
          </DialogHeader>
          {confirmBackfill && (() => {
            const { matched, total } = previewBackfill(confirmBackfill);
            const samples = matched.slice(0, 5);
            return (
              <div className="text-sm">
                <div className="mb-2">
                  {t('backfillDialog.matchSummary', { matched: matched.length, total })}
                </div>
                {samples.length > 0 ? (
                  <ul className="bg-secondary text-muted-foreground space-y-0.5 rounded-md p-2 font-mono text-[11px]">
                    {samples.map((tx) => (
                      <li key={tx.id} className="truncate">
                        {tx.date} · {tx.merchant} · ${Math.abs(tx.nativeAmount ?? tx.amount).toFixed(2)}
                      </li>
                    ))}
                    {matched.length > samples.length && (
                      <li className="italic">{t('backfillDialog.moreCount', { count: matched.length - samples.length })}</li>
                    )}
                  </ul>
                ) : (
                  <div className="text-muted-foreground italic">{t('backfillDialog.noMatches')}</div>
                )}
              </div>
            );
          })()}
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={() => confirmBackfill && onBackfill(confirmBackfill)}>
              <Icon name="check" size={14} />
              {t('backfillDialog.confirm')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!confirmDelete} onOpenChange={(o) => !o && setConfirmDelete(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('deleteDialog.title')}</DialogTitle>
            <DialogDescription>{t('deleteDialog.description')}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button variant="destructive" onClick={() => confirmDelete && onDelete(confirmDelete)}>
              {t('deleteDialog.confirm')}
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
  relativeDays,
  describeDict,
}: {
  rule: Rule | null;
  onClose: () => void;
  matchCountByRule: Map<string, number>;
  onEdit: (r: Rule) => void;
  onToggle: (r: Rule) => void;
  onAskDelete: (r: Rule) => void;
  onAskBackfill: (r: Rule) => void;
  relativeDays: (iso: string | null) => string | null;
  describeDict: ReturnType<typeof useDescribeDict>;
}) {
  const t = useTranslations('rules.detail');
  return (
    <Dialog open={!!rule} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="flex max-h-[85vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-md">
        <DialogHeader className="border-border shrink-0 border-b px-5 py-4">
          <DialogTitle className="font-serif text-xl italic">
            {rule?.name ?? t('ruleFallback')}
          </DialogTitle>
          <DialogDescription className="sr-only">{t('description')}</DialogDescription>
        </DialogHeader>
        {rule && (
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-4 text-sm">
            <div className="flex flex-wrap gap-2">
              <Button size="sm" onClick={() => onEdit(rule)}>
                <Icon name="edit" size={13} />{t('edit')}
              </Button>
              <Button size="sm" variant="outline" onClick={() => onToggle(rule)}>
                <Icon name={rule.isActive ? 'x' : 'check'} size={13} />
                {rule.isActive ? t('disable') : t('enable')}
              </Button>
              <Button size="sm" variant="outline" onClick={() => onAskBackfill(rule)}>
                <Icon name="sync" size={13} />{t('applyExisting')}
              </Button>
              <Button size="sm" variant="outline" onClick={() => onAskDelete(rule)} className="text-destructive">
                <Icon name="trash" size={13} />{t('delete')}
              </Button>
            </div>
            <DetailRow label={t('status')}>
              <span className={cn('font-medium', rule.isActive ? 'text-success' : 'text-muted-foreground')}>
                {rule.isActive ? t('active') : t('disabledStatus')}
              </span>
            </DetailRow>
            <DetailRow label={t('priority')}>{rule.priority}</DetailRow>
            <DetailRow label={t('rerunsOnEdit')}>{rule.runOnEdit ? t('yes') : t('no')}</DetailRow>
            <DetailRow label={t('appliedTo')}>
              {t('appliedCount', { count: matchCountByRule.get(rule.id) ?? 0 })}
            </DetailRow>
            <div>
              <div className="text-muted-foreground mb-1.5 font-mono text-[10px] uppercase tracking-wide">
                {t('condition')}
              </div>
              <pre className="bg-secondary rounded-md p-3 font-mono text-[11px] whitespace-pre-wrap">
                {describeCondition(rule.condition, describeDict)}
              </pre>
            </div>
            <div>
              <div className="text-muted-foreground mb-1.5 font-mono text-[10px] uppercase tracking-wide">
                {t('actions')}
              </div>
              <ol className="space-y-1 text-[12px]">
                {rule.actions.length === 0 ? (
                  <li className="text-muted-foreground italic">{t('noActions')}</li>
                ) : (
                  rule.actions.map((a, i) => (
                    <li key={i} className="bg-secondary rounded px-2 py-1 font-mono text-[11px]">
                      {i + 1}. {JSON.stringify(a)}
                    </li>
                  ))
                )}
              </ol>
            </div>
            <DetailRow label={t('lastBackfilled')}>
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
