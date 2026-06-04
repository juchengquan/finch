import { Icon } from '@/components/primitives';

/** Marks a `kind='refund'` row in transaction lists: a positive entry that nets
 *  against its category rather than counting as income. */
export function RefundBadge() {
  return (
    <span className="bg-success/10 text-success inline-flex shrink-0 items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium leading-none">
      <Icon name="sync" size={9} />
      Refund
    </span>
  );
}
