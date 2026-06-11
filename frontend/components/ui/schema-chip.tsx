// frontend/components/ui/schema-chip.tsx
// A small monospaced
// outline badge used in the mobile Pending and Transfers pages to
// label the schema/table context (e.g. "entries", "status = pending").
'use client';

import { Badge } from './badge';

export function SchemaChip({ label }: { label: string }) {
  return (
    <Badge variant="outline" className="text-muted-foreground font-mono text-[9px] tracking-wide">
      {label}
    </Badge>
  );
}
