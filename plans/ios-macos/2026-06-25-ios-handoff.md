# iOS/macOS handoff & sync-up

**Date:** 2026-06-25 (status refreshed 2026-06-26)
**Branch context:** all work targets `feat/frontend`. Snapshot taken @ `1fefe9d` (#347 merged).
**Purpose:** one page to sync between work sessions — what shipped, what's left, how we work, and how to avoid collisions. Pairs with the verified [parity-gap inventory](2026-06-25-ios-web-parity-gap-inventory.md) (the source of truth for web↔iOS gaps).

## How we work (conventions)

- **Flow per feature:** brainstorm → design spec → implementation plan → subagent-driven execution (one subagent per task, review between) → PR to `feat/frontend` → user merges → delete worktree/branch. Specs/plans live in `plans/ios-macos/<date>-<feature>-{design,plan}.md`.
- **Worktrees:** each feature in its own `git worktree` off `origin/feat/frontend` (e.g. `/tmp/finch-<slug>`); the user edits concurrently, so never stash/checkout in the main tree.
- **Commits:** **no `Co-Authored-By` trailer**. **Builds:** always FinchApp (iOS) **and** FinchMac (macOS); `xcodegen generate` after adding/removing files. **Engine tests:** `cd ios/FinchCore && swift test` — keep **ParityTests** green (additive selectors are safe; note `ListOptions` is decoded by the parity fixtures, so new non-optional fields need Codable defaults). FinchApp tests run via `xcodebuild test -only-testing:FinchAppTests` (not `swift test`).
- **CI:** docs-only PRs (`plans/**`, `*.md`) skip CI via `paths-ignore` (#278). iOS CI was ~halved (#276). **Note:** a PR can be merged while the long iOS check is still *pending* — confirm the iOS job goes green post-merge.
- **Sim verification caveat:** **SwiftUI sheets/menus do not open under AppleScript AX automation** — the feed filter sheet and toolbar **Menu** popovers register the press but don't present (menu items live in a separate AX window). Verify those by hand, or lean on engine unit tests for the logic. Seed DB state + AXPress by accessibility description where possible; tappable rows/buttons on a visible screen do work. (The Settings **gear** moved to the top-left, #339.)

## Shipped — web→iOS parity (Tier-1/2/3 from the inventory)

**Tier-1 — all closed:** Scheduled **calendar view** (#307) · Budgets **rollover UI** (#311) · **FX source + currency picker** (#302) · **Rules** builder CP2a/CP2b (#292, #297) · **Insights advice engine** CP1, core 6 rules (#323).

**Tier-2 — closed except one:** Accounts **reconcile status badge + pending/confirmed split** (#329) · **Activity saved searches** (per-ledger filter chips, #333) · **Budgets per-account filter** (#337). **Remaining:** the **guided reconcile session** (see below).

**Tier-3 — all closed:** Insights **`Ring` + `StackedBar`** primitives (#342) · Settings **theme toggle + language picker** (#338) · Budget create form **all 6 frequencies** (#340) · **Opening-balance display** in account detail (#347, also fixed Holdings cost basis).

## Shipped — iOS-original UX

- Edit-form parity with Add: status/account/refund-link (#283), currency (#296), counterparty suggestions (#312); **kind reclassification** in Edit (#319).
- Feed: result count + no-results + bulk confirm/delete (#293), filter by merchant (#308), **multi-tag filter Any/All** (#314), **sort options** date/amount (#321), **tappable account-detail transactions** (feed-parity rows, #341).
- Rows: refund badge (#298), tag colors (#301); **receipt thumbnails** in the Edit list (#331).
- Receipts: in-app preview / Quick Look (#289), **preview from a transaction row** (#327).
- Merchant detail screen (#306) + **deep-link to filtered feed** (#318).
- **Notifications:** cancel stale/disabled on refresh + end-to-end audit (#335).
- Polish: **Settings gear → top-left** (#339), **swap Refund/Adjust-Balance** order in Add (#341), **localize `AppTab.title`** so tab chrome translates / zh-Hans (#346).
- Docs/infra: parity inventory (#303, refreshed #343) + backlog reconcile (#313) + this handoff (#315/#324); CI cache+skip (#276/#278).

## Remaining web→iOS parity gaps

**One Tier-2 gap left:**
- **Accounts: guided reconcile session** — iOS's `ReconcileSheet` is a simple *statement-balance → auto-adjustment* form. The web has a guided session: **tick cleared transactions**, a **cleared-vs-target** progress display, **quick-add a missing transaction** inline, and **confirm-and-clear** pending rows. This was explicitly deferred when the reconcile badge/split shipped (#329) — it's a UX-model change, deserves its own spec. (Files: `WriteScreens/ReconcileSheet.swift`, `WriteScreens/AccountDetailView.swift`.)

Everything else in the inventory's Tier-1/2/3 is done. See the inventory for per-item detail.

## iOS-original enhancement backlog (not parity)

Tracked here + in the inventory. Status as of this snapshot:

| Item | Size | Status |
|---|---|---|
| Multi-tag filter (Any/All) | S | ✅ Done (#314) |
| Feed **sort options** (amount / oldest-first) | S | ✅ Done (#321) |
| **Merchant detail → pre-filtered feed** deep-link | S | ✅ Done (#318) |
| **Kind reclassification** in Edit (leg rebuild) | M | ✅ Done (#319) |
| Receipt **thumbnails** in the Edit list | S | ✅ Done (#331) |
| Preview a receipt **from a transaction row** | S | ✅ Done (#327) |
| **Notifications** end-to-end verification | M | ✅ Done (#335) |
| **Receipt scanning** (VisionKit) | M | open |
| **Insights/analytics expansion** (spend-by-merchant, net-worth-over-time) | M | open — `Ring`/`StackedBar` primitives landed (#342) but aren't wired into real Insights cards yet; the reports + wiring remain |
| **CloudKit sync maturity** | L | open (iOS-ahead scaffold; needs container provisioning + multi-device testing) |

**Not gaps (don't add back):** Goals = income budgets by design; "saved filter presets" = Activity saved searches (done #333).

## Collision avoidance

- 0 open PRs at this snapshot (@`1fefe9d`). Both sessions push frequently — **`git fetch` + re-read the inventory/this doc before picking**, and check `gh pr list --base feat/frontend --state open` (inspect the PR's *files*, not just the title).
- **Tier-1/2/3 are essentially done, so the two streams now overlap heavily — coordinate per-feature.** Recent division of labour:
  - *Other session:* Insights/charts (`Ring`/`StackedBar` #342, and likely the wiring follow-up), Settings/theme/i18n (#338, #346, an in-flight **localize-tab-titles** plan), budget frequencies (#340), notifications (#335).
  - *This session:* accounts/reconcile (#329), budgets per-account (#337), activity saved searches (#333), opening-balance (#347), UI tweaks (gear #339, tappable txns + Refund/Adjust swap #341).
- **Hot/shared files — check before editing:** `Tabs/ActivityTab.swift`, `WriteScreens/TransactionFilterSheet.swift`, `WriteScreens/EditTransactionSheet.swift`, `WriteScreens/AccountDetailView.swift`, `WriteScreens/BudgetSheet.swift`, `Tabs/SettingsTab.swift`, `Project/Projections+State.swift`, `Selectors/Selectors.swift`, `Common/ChartViews/*`.
- **Avoid right now (other session active):** Insights/charts wiring, Settings/theme, i18n/localization, budget add-form. **Clear for this session:** the guided reconcile session, receipt scanning, CloudKit.

## Pointers

- Source of truth for gaps: `2026-06-25-ios-web-parity-gap-inventory.md` (refreshed @`db6ab1c`, #343).
- Roadmap / audit: `IOS_MACOS_ROADMAP.md`, `IOS_MACOS_UI_GAP_AUDIT.md`, `IOS_MACOS_INDEX.md`.
- Per-feature specs/plans: `plans/ios-macos/2026-06-2*-*-{design,plan}.md`.
