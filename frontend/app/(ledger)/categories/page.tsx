'use client';

import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';

export default function CategoriesPage() {
  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Categories"
          trailing={<IconButton icon="dots"/>}
        />
      }
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="categories"/>
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {LEDGER.categoryTree.length} <span className="italic text-muted-foreground">groups</span>
          </div>
          <div className="mt-1.5 text-[13px] text-secondary-foreground">
            Two-level taxonomy. Parents hold the subcategories used on transactions.
          </div>
        </div>

        {LEDGER.categoryTree.map((cat) => (
          <div key={cat.parent} className="mb-2.5 rounded-[14px] border border-border bg-card p-4">
            <div className="flex items-center gap-3">
              <div className="h-3.5 w-3.5 flex-shrink-0 rounded-full" style={{ background: `oklch(0.65 0.13 ${cat.hue})` }}/>
              <div className="flex-1 text-sm font-medium">{cat.parent}</div>
              <span className="rounded bg-secondary px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] text-secondary-foreground">
                {cat.type}
              </span>
            </div>
            <div className="mt-3 flex flex-wrap gap-1.5">
              {cat.children.map((child) => (
                <span
                  key={child}
                  className="rounded-lg bg-secondary px-2.5 py-1 text-[11px] text-secondary-foreground"
                >
                  {child}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
    </MobilePage>
  );
}
