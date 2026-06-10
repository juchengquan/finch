# Finch

Personal finance tracker — multi-currency, multi-ledger, mobile-first with a responsive desktop shell.

## Stack

- **Next.js 16** (App Router, Turbopack) + **React 19**
- **TypeScript** (strict)
- **Tailwind CSS v4** + **shadcn/ui** (Radix-based components)
- **zustand** for the client-side store
- **SQLite** as the server-side source of truth (`better-sqlite3` under Node, `bun:sqlite` under Bun, WAL mode, file-backed)
- **lucide-react** icons, **next-themes** (light/dark), **sonner** (toasts)
- **Bun** for package manager and test runner

## Getting started

```bash
bun install
bun dev                    # http://localhost:3000
```

## Scripts

| Command | Purpose |
|---|---|
| `bun dev` | Start the dev server |
| `bun run build` | Production build |
| `bun run start` | Serve the production build (defaults to port 3000) |
| `bun run lint` | ESLint (flat config) |
| `bun run typecheck` | `tsc --noEmit` |
| `bun test lib` | Unit tests (Bun test runner) |
| `bun run test:e2e` | Playwright end-to-end tests |

## Architecture

```
app/
├── (main)/          # Consumer app — accounts, budgets, scheduled, insights, goals…
│   ├── layout.tsx   # Sidebar tabs + mobile bottom bar via PageShell
│   └── scheduled/   # Unified calendar + list for recurring bills, income, reminders
components/
├── PageShell.tsx     # Single responsive shell (sidebar≥768px / bottom tab on mobile)
├── primitives.tsx    # Money formatter, SVG charts
├── ui/               # shadcn/ui components
├── sqlite-backup-provider.tsx  # Settings → Database wiring (export / import / restore)
└── store-hydration.tsx  # Hydrates zustand store from server on load
lib/
├── store/            # per-domain zustand slices
├── select.ts         # Pure selectors over transactions (balance, spend, forecast)
├── derive.ts         # Derived computations from store
├── data.ts           # Static reference data + money formatters
├── api-client.ts     # Client ↔ server state sync (fetch / mutate)
└── db/               # SQLite layer — schema, seed, queries, mutations, state projection
```

### Data layers

1. **Static reference** (`data/*.json` + `lib/data.ts`) — read-only seed: ledgers, accounts, categories, default scheduled templates. Used as the pre-hydration fallback for the client lookups.
2. **Server-side SQLite** (`lib/db/`) — the **source of truth**. File-backed at `FINCH_DB_DIR/FINCH_DB_FILE` (`./.data/finch.sqlite3` by default), WAL mode, opened by the runtime-detecting `lib/db/driver.ts` (`better-sqlite3` under Node, `bun:sqlite` under Bun). Mutations land via `/api/mutate` inside a `BEGIN`/`COMMIT` wrapper; reads via `/api/state`.
3. **Client store** (`lib/store/`) — the zustand store is a mirror of #2, populated by `components/store-hydration.tsx` on load and patched after every mutation. The store is the in-memory working model for the UI, not the durability boundary.

### Money & currencies

Amounts are stored in the active ledger's base currency. Use `useMoney()` to display (auto-converts to user's chosen display currency). Use `fmtNative()` / `fmtNativeShort()` from `lib/data.ts` for amounts already denominated in their own currency.

### DB layer

`lib/db/` is layered (`core/` → `domain/` → `mutate.ts`) with one folder per first-class domain. See `frontend/db-architecture.md` for the full layout, the layer rules (enforced by ESLint), and a worked example for adding a new action.

## Remote access via Tailscale Serve

To expose the app at `https://your-hostname.ts.net/finch`:

```bash
# Production build (must use production — dev mode + basePath + Turbopack don't mix)
bun run build && bun run start

# Start Tailscale Serve (in another terminal)
tailscale serve --bg --set-path /finch http://127.0.0.1:3000
```

### How it works

- `next.config.ts` sets `basePath: '/finch'` so Next.js prefixes all links and asset URLs.
- `proxy.ts` (Next.js proxy, formerly middleware) prepends `/finch` to requests where Tailscale stripped it, so routing works.
- Both are disabled in dev mode (`NODE_ENV === 'development'`) — dev runs bare at `localhost:3000`.

### Changing the path prefix

Set `NEXT_PUBLIC_BASE_PATH` and rebuild:

```bash
NEXT_PUBLIC_BASE_PATH=/myapp bun run build && bun run start
tailscale serve --bg --set-path /myapp http://127.0.0.1:3000
```

The default is `/finch`. Change `next.config.ts`, `proxy.ts`, `lib/api-client.ts`, and `components/sqlite-backup-provider.tsx` only if you change the default itself.

### Dev vs production

| Mode | Command | URL | basePath | Proxy |
|---|---|---|---|---|
| Dev | `bun dev` | `localhost:3000` | `''` | no-op |
| Prod | `build && start` | `host.ts.net/finch` | `/finch` | active |

Run them on different ports to keep both available:

```bash
bun dev                          # :3000 — local development
bun run build && bun run start -p 3001  # :3001 — Tailscale remote
tailscale serve --bg --set-path /finch http://127.0.0.1:3001
```

## Theming

CSS variables in `app/globals.css` — light "warm editorial" / dark "noir". Toggle via theme control (next-themes). Finance-semantic tokens `--success` / `--warning` supplement the shadcn set. Display currency is per-ledger, set in Settings › Ledger (derived from `useLedger()` + the store; not a provider).

## Provider order

`app/layout.tsx`: `ThemeProvider` → `LedgerProvider` → `StoreHydration` + `SqliteBackupProvider` → children + `Toaster`
