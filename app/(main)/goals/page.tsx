'use client';

import { Ring, Money } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK } from '@/lib/data';

export default function GoalsPage() {
  const goals = MOCK.goals;
  const saved = goals.reduce((s, g) => s + g.saved, 0);
  const target = goals.reduce((s, g) => s + g.target, 0);
  const pct = Math.round((saved / target) * 100);

  return (
    <MobilePage
      header={<ScreenHeader title="Goals" trailing={<IconButton icon="plus" aria-label="New goal" />} />}
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Saved toward goals"
          value={<Money value={saved} mono={false} />}
          sublabel={
            <>
              of <Money value={target} /> · {pct}%
            </>
          }
        />
        <div className="bg-secondary mt-1 h-2 overflow-hidden rounded-full">
          <div className="bg-primary h-full" style={{ width: `${pct}%` }} />
        </div>
      </div>

      <div className="flex flex-col gap-2.5 px-5 pb-[120px]">
        {goals.map((g) => {
          const p = Math.round((g.saved / g.target) * 100);
          return (
            <div key={g.id} className="bg-card border-border flex items-center gap-4 rounded-xl border p-4">
              <Ring
                value={g.saved}
                max={g.target}
                size={60}
                stroke={6}
                color={`oklch(0.65 0.15 ${g.hue})`}
                track="var(--secondary)"
              >
                <span className="font-serif text-sm">{p}%</span>
              </Ring>
              <div className="min-w-0 flex-1">
                <div className="text-[15px] font-medium">{g.name}</div>
                <div className="text-muted-foreground mt-0.5 text-xs">ETA {g.eta}</div>
                <div className="mt-1 text-sm">
                  <Money value={g.saved} className="font-medium" />
                  <span className="text-muted-foreground"> / </span>
                  <Money value={g.target} className="text-muted-foreground" />
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </MobilePage>
  );
}
