# Multi-language / i18n — plan

Status: **proposed** (planning only — no code yet)
Scope: `frontend/` (Next.js app shell + Settings; **not** the user's ledger data)

> Adds runtime translation + locale-aware formatting to the web app. Initial
> locale set: **English (base) + Simplified Chinese (zh-CN)**. The `.finch`
> pack/data layer is untouched — translations are app chrome, not ledger
> content (category names, transaction notes, merchant names etc. stay as
> the user typed them).
>
> Native i18n on iOS/macOS goes through Apple's own `Localizable.strings` /
> `Localizable.stringsdict` story (see `IOS_MACOS_PLAN.md §11`); this plan
> doesn't bind that direction.

Today every label, dialog, toast, validation message, and error string in
the web app is hardcoded English. Money is already locale-aware via the
`useMoney` hook (`Intl.NumberFormat`), but everything else — dates, plurals,
chrome text — is English-only. This plan adds a proper i18n layer.

---

## 0. Confirmed product decisions

Decided going in; anything else is an open question (§12).

1. **Translate the chrome, not the data.** UI strings (buttons, dialogs,
   toasts, settings rows, validation messages) get translated. User-typed
   strings (category names, merchant names, ledger names, taglines,
   transaction notes, tag names) stay in whatever language the user typed
   them — no machine translation, no auto-rename. Two different concerns.
2. **English is base + fallback**, complete coverage required. Other
   locales (just `zh-CN` in v1) may be partial — a missing key falls back
   to the English source. No build-time error on missing keys; a CI guard
   (§9) reports coverage but doesn't fail the build.
3. **Locale list at v1: `en` + `zh-CN` only.** Smallest meaningful set.
   Adding `ja`, `es`, etc. is a follow-up + community contribution path.
4. **Per-device preference**, persisted to `localStorage` under
   `finch.locale`. Same model as the active ledger (PR #109) — your phone
   on Chinese shouldn't flip the desktop off English. SSR-safe via
   `useSyncExternalStore`. The default for a first-time visitor: the first
   match of `navigator.languages` against the supported set, falling back
   to `en`.
5. **Currency is orthogonal to locale.** Picking 中文 as your UI language
   does **not** change USD to RMB. The existing `useCurrency` /
   `CurrencyProvider` decision (per-ledger display currency from
   `app_state`) stands unchanged.
6. **Hand-translated, not machine.** Editorial tone is part of finch's
   brand; Google Translate would butcher it. Community/owner-curated
   catalogs in the repo, reviewed via PR like any other code.
7. **No localization in the `.finch` pack.** Translations are app-level
   chrome; the pack carries ledger data which is by definition user-typed.
   Packs round-trip across locales unchanged.

---

## 1. Current state

- Every UI string in `frontend/app/**` and `frontend/components/**` is a
  hardcoded English literal. Rough count: ≈ 350 distinct strings across
  ≈ 60 surfaces (page headers, dialogs, toasts, validation messages).
- **Money**: ✅ already locale-aware via `useMoney` / `Intl.NumberFormat`.
- **Dates**: mixed — `lib/data.ts` has a couple of formatters, most pages
  use ad-hoc `toLocaleDateString()` or hand-formatted strings.
- **Plurals**: every plural is a `count === 1 ? 'category' : 'categories'`
  ternary today. No CLDR plural categories.
- **Server errors**: `lib/db/mutations.ts` throws ≈ 30 English `Error`
  messages that propagate to client toasts via the `/api/mutate` route.
- **No i18n library installed.**

---

## 2. Scope: chrome vs data

| Layer | Translated? | Why |
|---|---|---|
| Nav labels, page titles, button text, dialog headers, settings rows | ✅ Yes | Chrome — finch's voice |
| Toast messages (success / error / info) | ✅ Yes | Chrome |
| Validation messages (form errors, mutation errors) | ✅ Yes | Chrome — comes from the codebase, not the user |
| Format hints / placeholders / helper text | ✅ Yes | Chrome |
| Category names, merchant names, ledger names, ledger tagline, tag names | ❌ No | User-typed data |
| Transaction notes, descriptions | ❌ No | User-typed data |
| Currency codes (USD, SGD, ...) | ❌ No | Standardised ISO 4217; localised symbol still flows through `Intl.NumberFormat` |
| Schema versions, internal ids | ❌ No | Technical |
| Account types (savings / credit_card / ...) | ✅ Yes | These ARE chrome — the user picks from a fixed list of CHECK-constraint values, displayed as friendly labels |
| Budget kind, transaction kind, scheduled frequency | ✅ Yes | Same — CHECK-constraint enums get a friendly localised label per option |

---

## 3. What changes vs what doesn't

| Layer | Changes? |
|---|---|
| Database schema | No |
| Mutations (the SQL) | No |
| `.finch` pack format | No |
| API route shapes | Slight — `/api/mutate` errors return `{ error: { code, params } }` instead of `{ error: string }` |
| Read paths / queries | No |
| App shell (`PageShell`, sidebar, bottom bar) | Every string `t('key')` |
| Settings | New "Language" row + every existing string keyed |
| Dialogs / toasts everywhere | Keyed |
| Validation throws in `mutations.ts` | Throw `new I18nError({ code, params })` instead of raw strings |
| `useMoney` | Unchanged (already locale-aware) |
| Date formatting | New `useFormat()` hook centralising `Intl.DateTimeFormat` |
| Tests | One new — every key in `en.json` resolves; coverage report for `zh-CN.json` |

---

## 4. Architecture

### 4.1 Library: `next-intl`

| Option | Pros | Cons |
|---|---|---|
| **A. `next-intl`** | Purpose-built for Next.js 16 App Router; ICU MessageFormat (proper plurals, gender, list); SSR-safe; ~30 kb gz | One dep; one config file |
| B. `react-intl` | Mature, large ecosystem | Heavier; predates App Router |
| C. Hand-rolled (`Intl` + tiny dispatcher) | Zero deps | Reinventing CLDR plural rules; no ICU |
| D. `i18next` + `react-i18next` | Most popular | Heaviest; multiple plugins; overkill |

**Decision: A** (`next-intl`). Cleanest fit for Next.js 16; ICU plurals via
`Intl.PluralRules` come for free; the message-loading + namespace patterns
match the App Router's RSC/client split.

### 4.2 Locale switching + persistence

- New `<I18nProvider>` wraps the tree (next to `LedgerProvider`,
  `ThemeProvider`).
- Active locale stored under `localStorage['finch.locale']`. Mirrors the
  active-ledger persistence pattern from `LedgerProvider` (PR #109):
  `useSyncExternalStore` for SSR safety + cross-tab updates via the
  `storage` event.
- First-time visitor: match `navigator.languages` against the supported
  set (`SUPPORTED = ['en', 'zh-CN']`), use the first hit. No prompt; quiet
  default.
- Settings → Account gains a "Language" row (Select dropdown).

### 4.3 Message catalog

```
frontend/messages/
├── en.json     (base; 100% coverage; the source of truth)
└── zh-CN.json  (partial OK; falls back to en per-key)
```

Keys are dotted, grouped by surface. Example shape:

```jsonc
{
  "nav": {
    "accounts": "Accounts",
    "activity": "Activity",
    "budgets": "Budgets",
    "scheduled": "Scheduled",
    "insights": "Insights"
  },
  "settings": {
    "language": {
      "row": "Language",
      "english": "English",
      "chinese": "中文(简体)"
    }
  },
  "ledger": {
    "deleteConfirm": {
      "title": "Delete \"{name}\"?",
      "blastRadius": "{accounts, plural, one {# account} other {# accounts}}, {txns, plural, one {# transaction} other {# transactions}}"
    }
  }
}
```

ICU plural syntax used for "N transactions" / "N transaction"; the existing
`count === 1 ? 'x' : 'xs'` ternaries collapse into the catalog.

### 4.4 Server-side error structure

Today `mutations.ts` throws English strings. They bubble through
`POST /api/mutate` as `{ error: string }` and land in a toast. To
localise mutation errors, we change the throw shape:

```ts
// before
throw new Error('A budget with this name and cycle already exists.');

// after
throw new I18nError('error.budget.duplicate', { name: 'Groceries' });
```

The route serialises to `{ error: { code, params } }`; the client
`mutate()` helper unpacks it and runs `t(code, params)` for the toast.

Implementation: a tiny `I18nError` class extending `Error`, a route shim
that JSON-serialises it, and a sweep through `mutations.ts` (~30 sites).
The sweep is one commit on its own.

### 4.5 Format helpers

New `useFormat()` hook returns:
- `fmtDate(date, style?)` — `Intl.DateTimeFormat` with the active locale.
- `fmtNumber(n, opts?)` — `Intl.NumberFormat` (non-currency; currency stays
  on `useMoney`).
- `fmtRelative(date)` — `Intl.RelativeTimeFormat` ("3 days ago" / "3天前").

This centralises the ad-hoc `toLocaleString` calls scattered across the app.

---

## 5. Initial locale list

| Locale | Status | Notes |
|---|---|---|
| `en` | Base | 100% coverage required |
| `zh-CN` | Initial target | Simplified Chinese; partial coverage OK; falls back to `en` per-key |

**Out of scope for v1**: `zh-TW`, `ja`, `ko`, `es`, `fr`, `de`. Added later
as community contributions or owner translation passes.

---

## 6. UI surfaces

- **Settings → Account**: new "Language" row, just below "Theme". Select
  with two options for v1.
- **Every existing component** with hardcoded strings: extracted to keys.
  Mechanical work; one commit per surface group is the natural rhythm
  (auth/nav, Settings, Activity, Add, Budgets, Insights, Scheduled,
  Pending, Transfers, Merchants/Categories/Tags/Rules, Transaction Detail,
  Lightbox).
- **Toasts (`sonner`)** route through `t()` directly.
- **Validation messages**: same — every form's `toast.error()` call gets
  a key.

---

## 7. Edge cases

- **Long strings overflowing UI**: a pass with German or Chinese will
  surface tight buttons. (Chinese is ~70% the width of English; German is
  ~30% longer.) Mostly fine for `zh-CN`.
- **Date format**: `Intl.DateTimeFormat('zh-CN')` outputs `2026/06/06`;
  the data layer continues to store `YYYY-MM-DD` ISO. Display only.
- **Plural rules**: Chinese has only `other` (no `one` / `few` / etc.) —
  ICU MessageFormat handles this transparently.
- **RTL layout**: not in v1 (no RTL languages in the initial set).
- **Mid-sentence interpolation** (e.g. "Reset restores the original sample
  data"): keep as a single key per sentence; don't split into "Reset" +
  "restores" + "data".
- **The `'personal'` literal fallbacks** flagged in
  `done/LEDGER_CRUD_PLAN.md §8`: these are not user-facing strings, no i18n
  impact. Tracked separately.
- **Currency vs locale**: `useCurrency` continues to control DISPLAY
  currency per ledger; `useLocale` controls UI chrome language. Pure
  orthogonal axes.

---

## 8. Implementation order (suggested commit split)

Each step ends with the full validation gate green (`bun run typecheck`,
`bun run lint`, `bun test lib`, `bun run build`).

1. **Library + provider + Settings row** — install `next-intl`, scaffold
   `<I18nProvider>`, persist via `localStorage`, add the Settings "Language"
   row + Select. Ship with one keyed surface end-to-end (Settings) so the
   pattern is concrete before mass extraction.
2. **Server error structure** — `I18nError` class + route shim +
   `mutations.ts` sweep (~30 throws). Client `mutate()` helper unpacks +
   localises. Tests cover the round-trip.
3. **Format helpers** — `useFormat()` hook; replace ad-hoc
   `toLocaleDateString` calls. Pure mechanical.
4. **Mass extraction** — every component's strings → `en.json` keys.
   Likely 2–3 sub-commits along the natural surface groupings (shell + nav,
   then admin pages, then transaction surfaces). Code review by surface
   group keeps diffs reviewable.
5. **`zh-CN.json` first pass** — partial coverage; nav, settings,
   primary CTAs, common error messages. Iteratively expand.

Total: 5–6 PR-sized commits, ≈ a week of focused work if done in one push.

---

## 9. Tests

- **Catalog integrity**: assert every key in `en.json` is a string (no
  accidental nesting bugs); assert every key referenced by source code
  exists in `en.json`. A small AST grep or `next-intl`'s own tooling
  catches drift.
- **Coverage report (informational, not blocking)**: percentage of `en`
  keys present in `zh-CN.json`. Surface in CI logs; don't fail the build.
- **Server error round-trip**: a mutation that throws `I18nError` lands
  as `{ error: { code, params } }` and the client `mutate()` helper
  rethrows with a localised message.
- **Locale switching**: `<I18nProvider>` reads from `localStorage`;
  changing the value triggers a re-render with the new strings.
- **Plural rules**: `t('budget.txnCount', { count: 1 })` and `{ count: 5 }`
  produce the right English forms; `zh-CN` falls into `other` correctly.

---

## 10. File touch list

| Path | Change |
|---|---|
| `frontend/messages/en.json` | New — 100% coverage. |
| `frontend/messages/zh-CN.json` | New — partial coverage; fallback to en. |
| `frontend/components/i18n-provider.tsx` | New — `<I18nProvider>` + `useLocale` + `useTranslation` re-exports. |
| `frontend/components/use-format.ts` | New — `fmtDate` / `fmtNumber` / `fmtRelative`. |
| `frontend/lib/i18n-error.ts` | New — `I18nError` class + serialisation helpers. |
| `frontend/lib/api-client.ts` | Update — `mutate()` unwraps structured errors and rethrows localised. |
| `frontend/app/api/mutate/route.ts` | Update — serialise `I18nError` to `{ error: { code, params } }`. |
| `frontend/lib/db/mutations.ts` | Sweep — ≈ 30 `throw new Error(...)` → `throw new I18nError(...)`. |
| `frontend/app/(main)/settings/account/page.tsx` | Update — new "Language" row. |
| `frontend/app/layout.tsx` | Update — wrap with `<I18nProvider>`. |
| Every surface with hardcoded strings | Mechanical sweep — `t('key')` calls. |
| `frontend/package.json` | New dep — `next-intl`. |
| `plans/MASTER_PLAN.md` | Strike "i18n" once shipped. |

---

## 11. Out of scope

- ❌ **RTL layout** (Arabic, Hebrew) — defer until a real user asks.
- ❌ **Translating user data** (category names, merchant names, ledger
  names, transaction notes, tag names). These are typed by the user;
  translating them would corrupt their records.
- ❌ **Automatic / machine translation** — editorial voice matters; we
  hand-translate.
- ❌ **Currency code localisation** (USD stays USD regardless of UI
  language; only the *symbol* + *grouping* localise via `Intl`).
- ❌ **Per-ledger language preference** — one language for the whole app.
- ❌ **Localised backups / packs** — translations don't travel in `.finch`.
- ❌ **Locales beyond `en` + `zh-CN`** for v1.

---

## 12. Open questions

1. **Auto-detect on first visit, or always default to `en`?** My recommendation
   is auto-detect against `navigator.languages` ∩ supported, fall back to
   `en`. Quiet default; user can flip in Settings if it's wrong.
2. **Where does `zh-CN` content live during the rollout** — committed
   in-PR by the implementer, or in a separate contribution PR? Likely
   in-PR for v1 (just one locale, owner-curated).
3. **CI strictness on missing `en` keys** — fail the build if a referenced
   key isn't in `en.json`? Recommend yes (it's a real bug); recommend no
   for missing `zh-CN` keys (that's just partial coverage).
4. **Should we add a CONTRIBUTING.md note** for translation PRs now, or
   defer until a community contributor shows up?
5. **Locale name display** — in the "Language" Select, do we render the
   locale's native name (English / 中文(简体)) or always in the current UI
   language? Native name is the convention.

---

## 13. Cross-references to `IOS_MACOS_PLAN.md`

- §11 "Accessibility & localization" updated in this PR to note the web's
  i18n approach + the orthogonal Apple-native path
  (`Localizable.strings`/`Localizable.stringsdict` + CLDR via `Foundation`).
- The decision to keep translations out of `.finch` packs preserves
  cross-app interop: a pack built on the iOS app in Japanese opens on the
  web app in Chinese without translation churn (only the user-typed
  category names cross over, which is correct).
