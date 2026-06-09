// lib/db/domain/tags/types.ts — public row + input/patch shapes for the tags
// domain. Keep this file free of SQL imports — it should be safe to import
// from any layer (UI components, route handlers, app_state) without pulling
// in the DB driver.

export interface Tag {
  id: string;
  ledgerId: string;
  name: string;
  color: string | null;
}

export interface TagPatch {
  name?: string;
  color?: string | null;
}
