# Finch — frontend

Personal expense tracker and money-management UI. Multi-currency,
multi-ledger, mobile-first with a responsive desktop shell.

> Preliminary frontend. All data is mock JSON in `data/`; there is no
> backend wired up yet.

## Stack

- **Next.js 16** (App Router, Turbopack) + **React 19**
- **TypeScript**
- **Tailwind CSS v4** + **shadcn/ui** (Radix-based components in `components/ui`)
- **lucide-react** icons, **next-themes** for light/dark
- **Bun** for install / lockfile (`bun.lock`)

## Getting started

```bash
bun install
bun run dev      # http://localhost:3000
```

Scripts:

| Script | Purpose |
| --- | --- |
| `bun run dev` | Start the dev server |
| `bun run build` | Production build |
| `bun run start` | Serve the production build |
| `bun run lint` | ESLint |
| `bun run typecheck` | `tsc --noEmit` |

## Architecture

- `app/(main)` — the consumer app (accounts, budgets, scheduled,
  insights, settings, …).
- `app/(ledger)` — the ledger-admin views (pending, transfers,
  merchants, recurring).
- `components/PageShell.tsx` — the single responsive shell: a sidebar +
  desktop header on ≥768px, a bottom tab bar on mobile. Page content
  renders once; breakpoint chrome is toggled with CSS.
- `components/MobileComponents.tsx` — shared page chrome (`MobilePage`,
  `ScreenHeader`, `PageHeader`, `IconButton`, …).
- `components/ui/*` — shadcn/ui components (button, card, dialog, select,
  switch, dropdown-menu, avatar, tooltip, progress, …).
- `components/primitives.tsx` — the lucide-backed `Icon` shim, money
  formatting, and SVG charts (sparkline, bar, donut, ring) that default to
  the theme token CSS variables.
- `lib/data.ts` — mock data loaders and money formatters. `fmtMoney`
  converts a USD base amount into the chosen display currency; `fmtNative`
  formats an amount already denominated in its own currency (ledger data).

## Theming

Design tokens live in `app/globals.css` using the shadcn CSS-variable
convention. The light theme is the "warm editorial" palette and the dark
theme is "noir"; toggle with the theme control (powered by `next-themes`).
Finance-semantic tokens `--success` / `--warning` supplement the standard
shadcn set. Display currency is switchable in **Settings** via
`CurrencyProvider`.
