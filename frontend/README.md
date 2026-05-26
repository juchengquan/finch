# Finch — frontend

Personal expense tracker and money-management UI. Multi-currency,
multi-ledger, mobile-first with a responsive desktop shell.

> Preliminary frontend. All data is mock JSON in `data/`; there is no
> backend wired up yet.

## Stack

- **Next.js 16** (App Router, Turbopack) + **React 19**
- **TypeScript**
- **CSS Modules** + design-token CSS custom properties (no Tailwind)
- **Radix UI** primitives (accordion, toggle, toggle-group)
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
- `components/primitives.tsx` — icons, money formatting, and SVG charts
  (sparkline, bar, donut, ring) that default to palette CSS variables.
- `lib/theme.ts` — palettes, font pairs and density presets. This is the
  source of truth for theme values; `TweaksContext` applies them to CSS
  custom properties at runtime and `styles/tokens.css` holds the
  no-JS defaults.
- `lib/data.ts` — mock data loaders and money formatters. `fmtMoney`
  converts a USD base amount into the chosen display currency; `fmtNative`
  formats an amount already denominated in its own currency (ledger data).

## Theming

Theme, typeface, density and display currency are user-switchable from
**Settings** and applied live via CSS custom properties.
