'use client';

import { useState } from 'react';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { EmptyState } from '@/components/empty-state';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from '@/components/ui/sheet';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { describeActions, describeCondition } from '@/lib/rules/describe';
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
  const [openRule, setOpenRule] = useState<Rule | null>(null);

  const ledgerRules = rules.filter((r) => r.ledgerId === activeId);
  // Per-rule "applied to N transactions" count from the projected store.
  const matchCountByRule = new Map<string, number>();
  for (const t of txns) {
    const ids = t.appliedRuleIds;
    if (!ids?.length) continue;
    for (const id of ids) matchCountByRule.set(id, (matchCountByRule.get(id) ?? 0) + 1);
  }

  return (
    <MobilePage header={<ScreenHeader title="Rules" />}>
      <div className="px-5 pb-[120px]">
        <div className="mb-4 text-muted-foreground text-xs leading-relaxed">
          Rules run automatically on every new transaction in <span className="text-foreground font-medium">{active.name}</span>.
          A matching rule can set the category, add a tag, rename the merchant,
          or split the row.
        </div>

        {ledgerRules.length === 0 ? (
          <EmptyState
            icon="sparkle"
            title="No rules yet"
            description="Rules categorise repeat merchants automatically. A builder ships next; for now, rules can be staged via the lib/db/queries/rules helpers."
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

      <RuleDetailSheet rule={openRule} onClose={() => setOpenRule(null)} matchCountByRule={matchCountByRule} />
    </MobilePage>
  );
}

function RuleDetailSheet({
  rule,
  onClose,
  matchCountByRule,
}: {
  rule: Rule | null;
  onClose: () => void;
  matchCountByRule: Map<string, number>;
}) {
  return (
    <Sheet open={!!rule} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full sm:max-w-md">
        <SheetHeader className="border-border border-b px-5 py-4">
          <SheetTitle className="font-serif text-xl italic">
            {rule?.name ?? 'Rule'}
          </SheetTitle>
          <SheetDescription className="sr-only">Rule detail</SheetDescription>
        </SheetHeader>
        {rule && (
          <div className="space-y-4 overflow-y-auto px-5 py-4 text-sm">
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
      </SheetContent>
    </Sheet>
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
