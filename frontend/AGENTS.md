<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

## DB layer (post-refactor, 2026-06)

The `frontend/lib/db/` directory is organized in three layers:

- `core/` — the DB engine. Plain DB access: driver, schema, entries (posting logic + auditLedger), entries-schema, repo (Exec/Row types), seed, server (Node/Bun open/close + getCachedAudit), paths, sealed-entry, checksum, pack, storage, test-utils. No business logic. No knowledge of any specific domain. The `I18nError` class itself lives one level up at `lib/i18n-error.ts` (shared with the client) — the wire-format helpers (`fromWireError`, `toWireError`) used by the server route also live there, not in `core/`.

- `domain/` — per-domain slices. One folder per first-class domain: `accounts/`, `accountGroups/`, `transactions/`, `budgets/`, `budgetGroups/`, `categories/`, `counterparties/`, `tags/`, `rules/`, `scheduled/`, `transfers/`, `holdings/`, `attachments/`, `ledgers/` (14 total). Each folder contains `queries.ts` (read + write SQL), `types.ts` (row + patch + input shapes), `errors.ts` (I18nError code constants), `mutations.ts` (per-action handlers as a `handlers` map), and `*.test.ts` files. `_shared/` and `_app/` are escape hatches for cross-cutting code; `_args.ts` is the central Args map; `_args.test.ts` is the union-shape smoke test. Note: `accountGroups/` and `budgetGroups/` are first-class domains, not merged into `accounts/` / `budgets/` — each has its own `queries.ts` / `mutations.ts` / `types.ts` / `errors.ts`.

- `mutate.ts` — the thin dispatch layer (53 lines). Imports per-domain `handlers` maps and routes `applyMutation(exec, action, args)` to the right handler. The only file that knows about all 74 actions.

Layer rules (enforced by ESLint `no-restricted-imports`):
- `core/*` cannot import from `domain/*`.
- `domain/<x>/` can only import from same-domain, `core/*`, `domain/_shared/`, `domain/_app/`, and the items re-exported from `domain/<x>/_deps.ts` (not yet created; 3 known cross-domain deps currently use direct `queries` imports: `transactions → attachments`, `rules → counterparties`, `scheduled → counterparties`).
- The route layer (`app/api/mutate/route.ts`) calls `applyMutation`; it does not import from per-domain files.
- External consumers (UI, route handlers, app state) import types from `lib/db/domain/<x>/types` and read SQL from `lib/db/domain/<x>/queries`; they do not import from `lib/db/domain/<x>/mutations`.

See `frontend/db-architecture.md` for the full layout + a worked example (adding a new action to the `tags` domain).
