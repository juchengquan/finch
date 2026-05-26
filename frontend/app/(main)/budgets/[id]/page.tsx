'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import { Ring, Money, MerchantGlyph, Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { MOCK, acctById } from '@/lib/data';
import { cn } from '@/lib/utils';

export default function BudgetDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const cat = MOCK.categories.find((c) => c.id === id) ?? MOCK.categories[0];
  const txns = MOCK.transactions.filter((t) => t.category === cat.id);
  const pct = Math.round((cat.spent / cat.budget) * 100);
  const over = cat.spent > cat.budget;
  const remaining = cat.budget - cat.spent;

  return (
    <MobilePage header={<ScreenHeader title={cat.name} back />}>
      <div className="px-5 pb-[120px]">
        <div className="text-muted-foreground mb-5 flex items-center gap-2 text-xs">
          <Link href="/budgets" className="text-muted-foreground">
            Budgets
          </Link>
          <Icon name="chev" size={11} />
          <span className="text-foreground">{cat.name}</span>
        </div>

        <div className="mb-6 flex items-center gap-5">
          <Ring
            value={cat.spent}
            max={cat.budget}
            size={104}
            stroke={10}
            color={over ? 'var(--destructive)' : 'var(--primary)'}
            track="var(--secondary)"
          >
            <div className="text-center">
              <div className="font-serif text-2xl leading-none">{pct}%</div>
              <div className="text-muted-foreground text-[9px] tracking-wider">USED</div>
            </div>
          </Ring>
          <div>
            <div className="font-serif text-3xl">
              <Money value={cat.spent} mono={false} />
            </div>
            <div className="text-muted-foreground mt-1 text-xs">
              of <Money value={cat.budget} />
            </div>
            <div
              className={cn(
                'mt-2 inline-flex items-center rounded-[10px] px-2.5 py-1 text-[11px] font-medium',
                over ? 'bg-destructive/10 text-destructive' : 'bg-success/10 text-success',
              )}
            >
              {over ? (
                <>
                  <Money value={-remaining} />
                  &nbsp;over
                </>
              ) : (
                <>
                  <Money value={remaining} />
                  &nbsp;left
                </>
              )}
            </div>
          </div>
        </div>

        <div className="mb-2 flex items-baseline justify-between px-1">
          <div className="font-serif text-lg italic">Transactions</div>
          <span className="text-muted-foreground font-mono text-[10px] tracking-wider">{txns.length}</span>
        </div>
        <div className="bg-card border-border overflow-hidden rounded-xl border">
          {txns.length === 0 && (
            <div className="text-muted-foreground p-4 text-center text-sm">No transactions yet</div>
          )}
          {txns.map((t, i) => (
            <Link
              key={t.id}
              href={`/tx/${t.id}`}
              className={cn('flex items-center gap-3 p-3.5', i && 'border-border border-t')}
            >
              <MerchantGlyph name={t.merchant} hue={cat.hue} size={36} />
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-medium">{t.merchant}</div>
                <div className="text-muted-foreground mt-0.5 text-[11px]">
                  {t.date.slice(5).replace('-', '/')} · {acctById(t.account).name}
                </div>
              </div>
              <Money value={t.amount} className="text-sm font-medium" />
            </Link>
          ))}
        </div>
      </div>
    </MobilePage>
  );
}
