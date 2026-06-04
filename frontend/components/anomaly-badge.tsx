import { Icon } from '@/components/primitives';

/** Marks a transaction whose magnitude is unusually far from the merchant's
 *  historical mean. Surfaced inline next to the merchant name so users notice
 *  "wait, $89 at Bali Beach is 4× my usual tab" — catches both fraud and
 *  honest mistakes. Threshold + min-sample-count live in the anomalyScore
 *  selector; this is purely cosmetic. */
export function AnomalyBadge({ zScore, mean }: { zScore: number; mean: number }) {
  const x = Math.round((zScore + Number.EPSILON) * 10) / 10;
  return (
    <span
      className="bg-warning/10 text-warning inline-flex shrink-0 items-center gap-0.5 rounded px-1.5 py-0.5 text-[10px] font-medium leading-none"
      title={`${x.toFixed(1)}× standard deviation from this merchant's average (≈ ${mean.toFixed(2)})`}
    >
      <Icon name="bell" size={9} />
      Unusual
    </span>
  );
}
