# UI layer architecture

> **Status:** post-refactor (2026-06-09). The `frontend/components/` directory is now layered: `ui/` → feature components → `app/`. 4-PR stack: #1 Icon shim, #2 store slices, #3 PageShell split, #4 primitive consolidation.

This is the contributor-facing reference for the post-refactor layout. The agent-facing orientation lives in `frontend/AGENTS.md`; this document is the deeper dive.

## Layers

### `frontend/components/ui/` — generic primitives

22 components: 10 shadcn wrappers + 12 promoted primitives. All kebab-case.

#### shadcn wrappers (10)
`accordion`, `badge`, `button`, `dialog`, `dropdown-menu`, `input`, `label`, `select`, `sonner`, `switch` (unchanged from `npx shadcn` output).

#### Promoted primitives (12)
| File | Symbol | Source (PR 4) |
|---|---|---|
| `icon-button.tsx` | `IconButton` | `icon-button.tsx` |
| `screen-header.tsx` | `ScreenHeader` | `screen-header.tsx` |
| `page-header.tsx` | `PageHeader` | `page-header.tsx` |
| `profile-chip.tsx` | `ProfileChip` | `profile-chip.tsx` |
| `schema-chip.tsx` | `SchemaChip` | `schema-chip.tsx` |
| `refund-badge.tsx` | `RefundBadge` | `refund-badge.tsx` |
| `status-badge.tsx` | `StatusBadge` | `StatusBadge.tsx` |
| `settings-item.tsx` | `SettingsItem` | `SettingsItem.tsx` |
| `insight-card.tsx` | `InsightCard` | `InsightCard.tsx` |
| `apr-vs-may.tsx` | `AprVsMay` | `AprVsMay.tsx` (codename dropped) |
| `cat-dot.tsx` | `CatDot` | `primitives.tsx:262` |
| `cat-bar.tsx` | `CatBar` | `primitives.tsx:267` |

Pure primitives — no business logic, no data fetching, no zustand reads. Composable.

### `frontend/components/<X>.tsx` — feature components

43 feature components (after PR 4 + PR A; 38 `.tsx` + 5 `.ts` helpers, of which 22 are in `ui/`). Kebab-case by default. Examples:
- `page-shell.tsx` (the dispatcher; currently in the allow-list as `PageShell.tsx`)
- `desktop-shell.tsx` / `mobile-shell.tsx` (the PageShell split from PR 3)
- `command-palette.tsx` (the ⌘K palette)
- `add-expense-form.tsx` / `edit-transaction-form.tsx` (the form bodies inside their respective dialogs)
- `rule-builder-dialog.tsx` / `merchant-picker-dialog.tsx` / etc. (renamed from `*-sheet.tsx` per PR 3)
- `mobile-tabs-editor.tsx` / `row-actions.tsx` (transitional — currently in the allow-list; candidates for kebab-case rename; their current PascalCase names will be migrated)

Each composes primitives from `components/ui/`, reads state from `lib/store/`, and renders. Pages are mostly `'use client'`.

### `frontend/components/icons.tsx` — typed lucide barrel

Sole entry point for lucide icons. ~50 re-exports (`ChevronUp as ChevU`, `ArrowDown as ArrowDl`, etc.). Consumers import from `@/components/icons`, not `lucide-react` directly. Typo'd icon names are tsc errors.

### `frontend/app/<page>.tsx` — the pages

The App Router. 19 routes in `(main)/`. Every page wraps in `<PageShell>` (the dispatcher from PR 3). Pages are mostly `'use client'`; the 3 server-component placeholders `goals`, `reports`, `settings` are deliberate redirects to `/budgets`, `/insights`, `/settings/account` (not unfinished features).

## File conventions

- `components/ui/*` — kebab-case. PascalCase forbidden (CI check).
- `components/<X>.tsx` — kebab-case by default. PascalCase allowed only via the allow-list in `scripts/check-component-filenames.sh` (currently 6 entries: 4 intentional — `PageShell.tsx`, `primitives.tsx`, `DesktopShell.tsx`, `MobileShell.tsx`; 2 transitional — `MobileTabsEditor.tsx`, `RowActions.tsx`).
- `components/icons.tsx` — single barrel, no other icon files.

## Layer rules (enforced by code review; the CI script enforces filenames only)

| From | To | Allowed? |
|---|---|---|
| `components/ui/*` | `components/ui/*` | ✓ |
| `components/ui/*` | `@/components/icons` | ✓ (typed lucide barrel is a one-off exception) |
| `components/ui/*` | `components/*` | ✗ (primitives don't reference features) |
| `components/ui/*` | `lib/store/*` | ✗ (primitives don't read state) |
| `components/*` | `components/ui/*` | ✓ (composing primitives) |
| `components/*` | `components/*` | ✓ (sibling feature components) |
| `components/*` | `lib/store/*` | ✓ (reading state, calling actions) |
| `components/*` | `@/components/icons` | ✓ (typed lucide imports) |
| `app/*` | `components/*` | ✓ (pages compose features) |
| `app/*` | `components/ui/*` | ✓ (pages compose primitives) |
| `app/*` | `lib/store/*` | ✓ (pages read state, call actions) |

## Icon pattern (PR 1)

```tsx
// Import the typed lucide symbol from the barrel:
import { ChevU, Bell, Fork } from '@/components/icons';

// Use in JSX:
<ChevU size={16} />
```

The old `<Icon name="chev-u" />` shim is deleted. Prefer typed lucide imports from `@/components/icons` for all new code. Typo'd names like `<Wrn />` are tsc errors.

## PageShell pattern (PR 3)

```tsx
// The 1 consumer (app/(main)/layout.tsx:54):
<PageShell tabs={mainTabs} navGroups={[ledgerGroup]} mobileTabs={mobileTabs} ...>
  {children}
</PageShell>

// Inside PageShell: JS-conditional dispatch
const isDesktop = useIsDesktop();
return isDesktop ? <DesktopShell {...props} /> : <MobileShell {...props} />;
```

The PageShell consumer (`app/(main)/layout.tsx:54-67`) passes all 10+ props (brand, tabs, navGroups, mobileTabs, activeTab, user, sidebarOpen, onSidebarToggle, showAdd, sidebarFooter); the dispatcher passes them through to whichever shell is active.

## Worked example: adding a new `components/ui/` primitive

Scenario: add a `<ColorDot />` primitive (a small colored circle for category colors) to `components/ui/`.

1. **Create the file** at `frontend/components/ui/color-dot.tsx`:
   ```tsx
   'use client';
   export function ColorDot({ color, size = 8 }: { color: string; size?: number }) {
     return <span className="inline-block rounded-full" style={{ background: color, width: size, height: size }} />;
   }
   ```

2. **Use it** from a feature component (e.g. `components/category-row.tsx`):
   ```tsx
   import { ColorDot } from '@/components/ui/color-dot';
   ...
   <ColorDot color={category.color ?? '#999'} />
   ```

3. **The CI script** (`bun run check:naming`) accepts the new kebab-case file. No further action needed.

## Test counts (post-PR 4)

- Total: 534 pass / 0 fail (matches the PR 3 baseline; PR 4 is pure refactor + docs).
- The 44 `useFinanceStore` consumers still work (PR 2 preserved the import path).
- The 388 `<Icon name="...">` call sites across 52 files are gone (PR 1; each was replaced with a typed lucide import from `@/components/icons`).
- The 5 `*-sheet.tsx` files are renamed (PR 3).
- The 12 promoted primitives are in `components/ui/` (PR 4).
- The 7-file allow-list passes `bun run check:naming`.
