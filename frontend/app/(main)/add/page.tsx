'use client';

import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';

export default function AddExpensePage() {
  return (
    <MobilePage
      header={
        <ScreenHeader
          back
          title="Add expense"
        />
      }
    >
      <div className="flex flex-col gap-3.5 px-5 pt-4 pb-[120px]">
        <div className="pt-5 text-center">
          <div className="text-muted-foreground mb-3.5 font-mono text-[10px] tracking-[1.5px]">AMOUNT</div>
          <div className="flex items-baseline justify-center gap-1.5">
            <span className="text-muted-foreground mt-[18px] self-start font-serif text-[32px]">$</span>
            <span className="font-serif text-[84px] leading-none font-normal -tracking-[3px]">42</span>
            <span className="text-muted-foreground font-serif text-[40px]">.18</span>
          </div>
        </div>

        <div>
          <div className="border-border flex items-center gap-3.5 border-b px-5 py-3.5">
            <div className="bg-secondary text-secondary-foreground flex size-8 shrink-0 items-center justify-center rounded-2xl"><Icon name="tag" size={15}/></div>
            <div className="min-w-0 flex-1">
              <div className="text-muted-foreground text-[11px] tracking-[0.4px] uppercase">Merchant</div>
              <div className="mt-px text-[15px]">Auto-detected</div>
            </div>
          </div>
          <div className="border-border flex items-center gap-3.5 border-b px-5 py-3.5">
            <div className="bg-secondary text-secondary-foreground flex size-8 shrink-0 items-center justify-center rounded-2xl"><Icon name="fork" size={15}/></div>
            <div className="min-w-0 flex-1">
              <div className="text-muted-foreground text-[11px] tracking-[0.4px] uppercase">Category</div>
              <div className="mt-px text-[15px]">Food & Dining</div>
            </div>
            <Icon name="chev" size={14} className="text-muted-foreground"/>
          </div>
          <div className="border-border flex items-center gap-3.5 border-b px-5 py-3.5">
            <div className="bg-secondary text-secondary-foreground flex size-8 shrink-0 items-center justify-center rounded-2xl"><Icon name="wallet" size={15}/></div>
            <div className="min-w-0 flex-1">
              <div className="text-muted-foreground text-[11px] tracking-[0.4px] uppercase">Account</div>
              <div className="mt-px text-[15px]">Amex Gold · 1009</div>
            </div>
            <Icon name="chev" size={14} className="text-muted-foreground"/>
          </div>
          <div className="border-border flex items-center gap-3.5 border-b px-5 py-3.5">
            <div className="bg-secondary text-secondary-foreground flex size-8 shrink-0 items-center justify-center rounded-2xl"><Icon name="calendar" size={15}/></div>
            <div className="min-w-0 flex-1">
              <div className="text-muted-foreground text-[11px] tracking-[0.4px] uppercase">Date</div>
              <div className="mt-px text-[15px]">Today</div>
            </div>
            <Icon name="chev" size={14} className="text-muted-foreground"/>
          </div>
        </div>

        <button type="submit" className="bg-foreground text-background mt-2 flex h-[54px] cursor-pointer items-center justify-center rounded-[27px] text-base font-medium -tracking-[0.2px]">
          Save expense
        </button>
      </div>
    </MobilePage>
  );
}
