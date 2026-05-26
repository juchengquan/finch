'use client';

import { Money } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { SCHEDULED_ITEMS } from '@/lib/data';
import { ScheduledItem } from '@/components/ScheduledItem';

export default function ScheduledPage() {
  const totalOutgoing = SCHEDULED_ITEMS.filter(i => i.amount < 0).reduce((s, i) => s + i.amount, 0);
  const totalIncoming = SCHEDULED_ITEMS.filter(i => i.amount > 0).reduce((s, i) => s + i.amount, 0);
  const netTotal = totalIncoming + totalOutgoing;

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Scheduled"
          trailing={<IconButton icon="search"/>}
        />
      }
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Next 30 days"
          value={<Money value={netTotal} mono={false} className="font-serif"/>}
          sublabel={
            <span className="text-success">+<Money value={totalIncoming}/> incoming</span>
          }
        />
      </div>

      <div className="px-5 pb-[120px]">
        {SCHEDULED_ITEMS.map((item, i) => (
          <ScheduledItem key={i} item={item}/>
        ))}
      </div>
    </MobilePage>
  );
}
