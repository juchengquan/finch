<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

## DB layer (post-refactor, 2026-06)

The `frontend/lib/db/` directory is organized in three layers:

- `core/` — the DB engine. Plain DB access: driver, schema, entries (posting logic + auditLedger), entries-schema, repo (Exec/Row types), seed, server (Node/Bun open/close + getCachedAudit), paths, sealed-entry, checksum, pack, storage, test-utils. No business logic. No knowledge of any specific domain. The `I18nError` class itself lives one level up at `lib/i18n-error.ts` (shared with the client) — the wire-format helpers (`fromWireError`, `toWireError`) used by the server route also live there, not in `core/`.

- `domain/` — per-domain slices. One folder per first-class domain: `accounts/`, `accountGroups/`, `transactions/`, `budgets/`, `budgetGroups/`, `categories/`, `counterparties/`, `tags/`, `rules/`, `scheduled/`, `transfers/`, `holdings/`, `attachments/`, `ledgers/` (14 total). Each folder contains `queries.ts` (read + write SQL), `types.ts` (row + patch + input shapes), `errors.ts` (I18nError code constants), `mutations.ts` (per-action handlers as a `handlers` map — present in every domain except `attachments/` and `budgetGroups/`, which are queries-only), and `*.test.ts` files. `_shared/` and `_app/` are escape hatches for cross-cutting code; `_args.ts` is the central Args map; `_args.test.ts` is the union-shape smoke test. Note: `accountGroups/` and `budgetGroups/` are first-class domains, not merged into `accounts/` / `budgets/`. `accountGroups/` has its own full set (`queries.ts` / `mutations.ts` / `types.ts` / `errors.ts`); `budgetGroups/` is queries-only — its 3 group actions live in `budgets/mutations.ts`.

- `mutate.ts` — the thin dispatch layer (53 lines). Imports per-domain `handlers` maps and routes `applyMutation(exec, action, args)` to the right handler. The only file that knows about all 74 actions.

Layer rules (enforced by ESLint `no-restricted-imports`):
- `core/*` cannot import from `domain/*`.
- `domain/<x>/` can only import from same-domain, `core/*`, `domain/_shared/`, `domain/_app/`, and the items re-exported from `domain/<x>/_deps.ts` (not yet created; 4 known cross-domain deps currently use direct `queries` imports: `transactions → attachments`, `budgets → budgetGroups`, `rules → counterparties`, `scheduled → counterparties`).
- The route layer (`app/api/mutate/route.ts`) calls `applyMutation`; it does not import from per-domain files.
- External consumers (UI, route handlers, app state) import types from `lib/db/domain/<x>/types` and read SQL from `lib/db/domain/<x>/queries`; they do not import from `lib/db/domain/<x>/mutations`.

See `frontend/db-architecture.md` for the full layout + a worked example (adding a new action to the `tags` domain).

## UI layer (post-refactor, 2026-06)

The `frontend/components/` directory is organized in three layers:

- `ui/` — generic primitives. 10 shadcn wrappers (the original `npx shadcn` output) + 12 promoted primitives (chips, badges, headers). All kebab-case. New primitives are added here.
- `components/<X>.tsx` — feature components (PageShell, DesktopShell, MobileShell, command-palette, add-expense-form, etc.). Kebab-case by default; PascalCase only via the allow-list in `scripts/check-component-filenames.sh` (currently 4 entries — PageShell.tsx, primitives.tsx, DesktopShell.tsx, MobileShell.tsx).
- `icons.tsx` — the typed lucide barrel. Sole entry point for lucide icons. Consumers import from `@/components/icons`, not `lucide-react` directly.

Layer rules (enforced by code review; the CI script enforces filenames only):
- `components/ui/*` is pure primitives — no business logic, no data fetching. The shadcn wrappers are thin wrappers; the promoted primitives are similarly focused.
- `components/<X>.tsx` is feature components — they compose primitives, fetch data, render pages.
- `app/<page>.tsx` is the page itself — imports from `components/*` and `lib/*`.

Renames that landed in the 4-PR refactor:
- `components/PageShell.tsx` is a 30-line dispatcher (was 366 lines; PR 3 split it into DesktopShell + MobileShell).
- 5 `*-sheet.tsx` files renamed to `*-dialog.tsx` (they all use shadcn `Dialog`, not a real bottom-sheet).

See `frontend/ui-architecture.md` for the full layout, the per-file convention, the layer rules table, the icon pattern, and a worked example (adding a new `components/ui/` primitive).
