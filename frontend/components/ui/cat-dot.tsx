// frontend/components/ui/cat-dot.tsx — extracted from
// primitives.tsx:262 (was 3 lines; PR 4). A small inline-block
// category-coloured circle used as a row indicator (e.g. in the
// activity feed, budget rollups).

const FALLBACK_CAT_COLOR = '#9ca3af';

export function CatDot({ color, size = 8 }: { color: string | null | undefined; size?: number }) {
  return <span className="inline-block rounded-full" style={{ width: size, height: size, background: color || FALLBACK_CAT_COLOR }} />;
}
