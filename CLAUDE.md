# CLAUDE.md

Guidance for Claude Code in this repository.

## What finch is — one domain, two front-ends

finch is a personal-finance **ledger**: a double-entry SQLite model of accounts,
transactions, budgets, categories, counterparties, tags, transfers, scheduled items,
holdings, FX rates, and multiple ledgers (each with a per-ledger display currency).
Domain model: `plans/database_design_en.md`.

Two **independent front-ends** implement that model:

- **Native — `ios/`** — SwiftUI app (iOS · macOS · watchOS · Widget · Share) over the
  `FinchCore` Swift engine, kept at behavioral parity with the web DB. **The current
  focus of active work.** Full guide: **`ios/CLAUDE.md`**. Native may add features ahead
  of the web and feed them back.
- **Web — `frontend/`** — Next.js 16 / React 19 / TypeScript (App Router), file-backed
  SQLite as source of truth. Documented below (+ `frontend/AGENTS.md`, `frontend/README.md`).

`plans/` holds design docs, not code: `MASTER_PLAN.md` (design-vs-implementation roadmap),
`plans/ios-macos/` (native specs; entry `IOS_MACOS_INDEX.md`), `frontend_design/` (web
prototype). The `ios/` Xcode projects are **XcodeGen-generated and git-ignored**
(`xcodegen generate --spec project.yml,project-mac.yml`); build/test via `swift test`
(FinchCore) or the `FinchApp` scheme.

---

Everything below covers the **web app (`frontend/`)**; all commands run from `frontend/`.
Server API: 9 route groups under `app/api/` (12 `route.ts` files) — `/api/mutate` (write), `/api/state` (read),
`/api/accounts`, `/api/attachments`, `/api/backups`, `/api/db-info`, `/api/export`,
`/api/import`, `/api/restore-backup`. The client store hydrates from `/api/state` and
patches locally after every `/api/mutate`.

## Commands (from `frontend/`; Bun — `bun.lock`)

```bash
bun install
bun dev                  # dev server at http://localhost:3000
bun run build            # production build
bun run lint             # eslint (flat config, eslint.config.mjs)
bun run typecheck        # tsc --noEmit
bun test lib             # unit tests (bun test runner, lib/**/*.test.ts)
bun run test:e2e         # Playwright e2e (e2e/), needs a build/dev server
```

Single test file: `bun test lib/derive.test.ts`. CI mirrors these in
`.github/workflows/ci.yml`.

## Critical: Next.js 16 ≠ your training data

Next.js 16 has breaking changes. Before writing routing/server code, read the relevant
guide in `frontend/node_modules/next/dist/docs/` and heed deprecations (also in
`frontend/AGENTS.md`).

## Architecture

**Stack:** Tailwind v4 + **shadcn/ui** (`components/ui/*`), **zustand**, **lucide-react**
(via the typed barrel `components/icons.tsx`, ~50 re-exports), **next-themes**, **sonner**.
Fonts via `next/font` in `app/layout.tsx`.

**Routing & shell:** one route group `(main)/`; its layout renders
**`components/PageShell.tsx`** — a **single-render responsive shell** (content renders
once; chrome switches by CSS at `md`/768px: sidebar + top bar vs fixed bottom tabs).
Consumer sections are the primary `tabs`; the ledger-admin pages (pending, transfers,
merchants, categories, tags, fx, system) are a labeled **`navGroups`** entry — desktop
sidebar only; reach them on mobile via ⌘K or in-content links. Route groups don't affect
URLs. On detail routes (`/<section>/<id>`) the top bar derives a "Section › Name"
breadcrumb via `BREADCRUMB_SECTIONS` (accounts/budgets/transfers/recurring); detail pages
mark their in-content breadcrumb `md:hidden`. Pages are mostly `'use client'`.

**Data & state — three layers:**
1. **Static reference data** — `lib/data.ts` exports `MOCK` and `LEDGER` from
   `data/*.json`, plus lookups (`acctById`, `catById`) and formatters. Read-only seed.
2. **Live state** — `lib/store/`: 14 per-domain zustand slices
   (`lib/store/<domain>/{state,actions}.ts`, wired in `lib/store/index.ts`), seeded from
   `data/*.json` and hydrated on load from the server (`components/store-hydration.tsx`). Read via
   `useFinanceStore(...)`. Every mutation calls `syncMutation(...)` → POST `/api/mutate`;
   the server returns fresh projected state that replaces the slice. The store is a
   working model, **not** the source of truth.
3. **The SQLite DB** — `lib/db/*`, file-backed, authoritative
   (`FINCH_DB_DIR`/`FINCH_DB_FILE`, default `./.data/finch.sqlite3`). Cross-runtime
   driver (`lib/db/driver.ts`): `better-sqlite3` under Node, `bun:sqlite` under Bun,
   same `Exec` shape. **WAL mode** (`synchronous=NORMAL`); no in-memory snapshot dance —
   **the file IS the live DB**. Export = `VACUUM INTO` tmp; import = close → swap file →
   reopen.

`lib/derive.ts` holds pure selectors (`accountBalance`, `categorySpent`, `netWorth`,
`monthSpent`, `monthIncome`) — compute figures, don't store them.

**Money & currencies (easy to get wrong):** amounts are stored in the **active ledger's
base currency** — never print raw amounts.
- `useMoney()` (`components/use-money.ts`) → `fmt`/`short`, converting base → display
  currency. Use for store/MOCK amounts.
- `fmtNative`/`fmtNativeShort` (`lib/data.ts`) format an amount already in its own
  currency (e.g. FX rows) — no conversion.
- Active ledger: `useLedger()` (`components/ledger-provider.tsx`); display currency:
  `useCurrency()` (`components/currency-provider.tsx`) — **per-ledger** (DB-backed
  `displayCurrencyByLedger`, defaults to that ledger's base until set in Settings › Ledger).

**Theming:** shadcn CSS variables in `app/globals.css` (light "warm editorial", dark
"noir"), toggled by `next-themes`. No `lib/theme.ts` / `styles/tokens.css`. Use semantic
Tailwind classes (`bg-card`, `text-muted-foreground`, `border-border`, `text-success`,
`text-warning`). `components/primitives.tsx` holds `Money` + the SVG chart primitives (Sparkline,
BarChart, AreaChart, Donut, StackedBar, Ring, Sankey, CalendarHeatmap, MerchantGlyph),
all reading the token variables.

**Provider order** (`app/layout.tsx`): `ThemeProvider` → `LedgerProvider` →
`StoreHydration` + `SqliteBackupProvider` → children + `Toaster`. (Display currency is
not a provider — `useCurrency()` derives it from `useLedger()` + the store.)

## Conventions

- Import alias `@/*` → `frontend/` root; TypeScript `strict` on.
- Customizing a shadcn component in `components/ui/*` is fine when it's the only
  consumer (e.g. `AccordionTrigger`'s `chevronSide` prop for the Accounts page).
