# iOS/macOS handoff & sync-up

**Date:** 2026-06-25 (status refreshed 2026-06-27)
**Branch context:** all work targets `feat/frontend`. Snapshot taken @ `5883551` (#374 merged). **All web→iOS parity gaps (Tier-1/2/3) are closed; the native-surfaces "deepen widgets" sub-project is also complete.**
**Purpose:** one page to sync between work sessions — what shipped, what's left, how we work, and how to avoid collisions. Pairs with the verified [parity-gap inventory](2026-06-25-ios-web-parity-gap-inventory.md) (the source of truth for web↔iOS gaps).

## How we work (conventions)

- **Flow per feature:** brainstorm → design spec → implementation plan → subagent-driven execution (one subagent per task, review between) → PR to `feat/frontend` → user merges → delete worktree/branch. Specs/plans live in `plans/ios-macos/<date>-<feature>-{design,plan}.md`.
- **Worktrees:** each feature in its own `git worktree` off `origin/feat/frontend` (e.g. `/tmp/finch-<slug>`); the user edits concurrently, so never stash/checkout in the main tree.
- **Commits:** **no `Co-Authored-By` trailer**. **Builds:** always FinchApp (iOS) **and** FinchMac (macOS); `xcodegen generate` after adding/removing files. **Engine tests:** `cd ios/FinchCore && swift test` — keep **ParityTests** green (additive selectors are safe; note `ListOptions` is decoded by the parity fixtures, so new non-optional fields need Codable defaults). FinchApp tests run via `xcodebuild test -only-testing:FinchAppTests` (not `swift test`).
- **CI:** docs-only PRs (`plans/**`, `*.md`) skip CI via `paths-ignore` (#278). iOS CI was ~halved (#276). **Note:** a PR can be merged while the long iOS check is still *pending* — confirm the iOS job goes green post-merge.
- **Sim verification caveat:** **SwiftUI sheets/menus do not open under AppleScript AX automation** — the feed filter sheet and toolbar **Menu** popovers register the press but don't present (menu items live in a separate AX window). Verify those by hand, or lean on engine unit tests for the logic. Seed DB state + AXPress by accessibility description where possible; tappable rows/buttons on a visible screen do work. (The Settings **gear** moved to the top-left, #339.)

## Shipped — web→iOS parity (Tier-1/2/3 from the inventory)

**Tier-1 — all closed:** Scheduled **calendar view** (#307) · Budgets **rollover UI** (#311) · **FX source + currency picker** (#302) · **Rules** builder CP2a/CP2b (#292, #297) · **Insights advice engine** CP1, core 6 rules (#323).

**Tier-2 — all closed:** Accounts **reconcile status badge + pending/confirmed split** (#329) · **Activity saved searches** (per-ledger filter chips, #333) · **Budgets per-account filter** (#337) · **guided reconcile session** — CP1 tick-cleared + cleared-vs-target tracker + Done/Adjust finish (#355) and CP2 quick-add-missing + confirm-and-clear (#358).

**Tier-3 — all closed:** Insights **`Ring` + `StackedBar`** primitives (#342) · Settings **theme toggle + language picker** (#338) · Budget create form **all 6 frequencies** (#340) · **Opening-balance display** in account detail (#347, also fixed Holdings cost basis).

## Shipped — iOS-original UX

- Edit-form parity with Add: status/account/refund-link (#283), currency (#296), counterparty suggestions (#312); **kind reclassification** in Edit (#319).
- Feed: result count + no-results + bulk confirm/delete (#293), filter by merchant (#308), **multi-tag filter Any/All** (#314), **sort options** date/amount (#321), **tappable account-detail transactions** (feed-parity rows, #341).
- Rows: refund badge (#298), tag colors (#301); **receipt thumbnails** in the Edit list (#331).
- Receipts: in-app preview / Quick Look (#289), **preview from a transaction row** (#327).
- Merchant detail screen (#306) + **deep-link to filtered feed** (#318).
- **Notifications:** cancel stale/disabled on refresh + end-to-end audit (#335).
- Polish: **Settings gear → top-left** (#339), **swap Refund/Adjust-Balance** order in Add (#341).
- **Native surfaces — "deepen widgets" sub-project (complete):** CP1 lock-screen / accessory families (#364) · CP2 configurable **Account + Budget** widgets (snapshot expansion + `AppIntentConfiguration`, #369) · CP3 interactive **quick-add** (`finch://add` scheme + `onOpenURL` + `.widgetURL`, #374). (Pre-existing scaffolds App Intents/Siri, Spotlight, Share extension, basic Watch glance remain as-is.)
- **Other session (recent):** recurring-charge detector (#359), flat dated activity feed (#368), confirm-transaction deletes + Ledger overflow menu (#370), budget-cycle edit folded into the edit sheet, gitignore (#366).
- **Full zh-Hans localization:** tab titles (#346) → **catalog refresh** capturing +131 stale keys (#349) → **the 96 remaining strings + nav-title bypass fix** (#350). Catalog 456 keys / 441 translated; 15 intentional format tokens. *(The ~97 #350 strings are AI-authored — native review advised before release.)*
- Docs/infra: parity inventory (#303, refreshed #343) + backlog reconcile (#313) + this handoff (#315/#324); CI cache+skip (#276/#278).

## Remaining web→iOS parity gaps

**None — all Tier-1/2/3 parity gaps from the inventory are closed** (the guided reconcile session, the last one, shipped in #355/#358). Anything further is **iOS-original backlog**, not web parity — see below. Web→iOS feature parity is, as of this snapshot, complete.

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
| **zh-Hans translation coverage** | M | ✅ Done (#346/#349/#350) — 441/456 keys; AI-authored, native review advised |
| Widgets: **lock-screen / accessory families** | S | ✅ Done (#364) |
| Widgets: **configurable Account + Budget** | M | ✅ Done (#369) |
| Widgets: **interactive quick-add** (tap → Add) | S | ✅ Done (#374) |
| **Watch: complication + on-wrist quick-add** | M | open — next native-surface sub-project; needs a watch snapshot/WCSession path (the watch is self-contained, no FinchCore dep) |
| Widget **account pre-fill** for quick-add (`finch://add?account=<id>`) | S | open — small follow-up to widgets CP3 |
| **Insights advice CP2** (5 day-of-week/day-of-month pattern rules) | S | open — deferred from the advice-engine CP1 (#323) |
| **Receipt scanning** (VisionKit) | M | open — *device-only* (no sim camera) |
| **Insights/analytics expansion** (spend-by-merchant, net-worth-over-time) | M | open — `Ring`/`StackedBar` primitives landed (#342) but aren't wired into real Insights cards yet; the reports + wiring remain |
| **CloudKit sync maturity** | L | open (iOS-ahead scaffold; needs container provisioning + multi-device testing) |
| **Polish themes** (not formally specced) | — | open — accessibility pass (VoiceOver/Dynamic Type/contrast), PDF/CSV/tax export, iPad multi-column + macOS keyboard/menus |

**Not gaps (don't add back):** Goals = income budgets by design; "saved filter presets" = Activity saved searches (done #333).

## Collision avoidance

- 0 open PRs at this snapshot (@`5883551`). Both sessions push frequently — **`git fetch` + re-read the inventory/this doc before picking**, and check `gh pr list --base feat/frontend --state open` (inspect the PR's *files*, not just the title).
- **All parity is done — only the iOS-original backlog remains, so coordinate per-feature.** Recent division of labour:
  - *Other session:* Insights/charts (`Ring`/`StackedBar` #342, + the wiring follow-up), Settings/theme/i18n (#338, #340, zh-Hans #346/#349/#350), roadmap docs (#354), notifications (#335).
  - *This session:* accounts/reconcile (badge+split #329, **guided reconcile session #355/#358**), budgets per-account (#337), activity saved searches (#333), opening-balance (#347), UI tweaks (gear #339, tappable txns + Refund/Adjust swap #341), **widgets sub-project CP1/2/3 (#364/#369/#374)** + the `finch://` deep-link scheme.
- **Hot/shared files — check before editing:** `Tabs/ActivityTab.swift`, `WriteScreens/TransactionFilterSheet.swift`, `WriteScreens/EditTransactionSheet.swift`, `WriteScreens/AccountDetailView.swift`, `WriteScreens/BudgetSheet.swift`, `Tabs/SettingsTab.swift`, `Project/Projections+State.swift`, `Selectors/Selectors.swift`, `Common/ChartViews/*`.
- **Avoid right now (other session active):** Insights/charts wiring, Settings/theme, i18n/localization, activity-feed structure. **Clear for this session:** the **Watch** sub-project, widget account pre-fill, Insights advice CP2, receipt scanning (device-only), CloudKit, the polish themes. New `finch://` URL scheme + `DeepLinkRouter.handle` are the deep-link entry point for future widget/Watch routes.

## Pointers

- Source of truth for gaps: `2026-06-25-ios-web-parity-gap-inventory.md` (refreshed @`db6ab1c`, #343).
- Roadmap / audit: `IOS_MACOS_ROADMAP.md`, `IOS_MACOS_UI_GAP_AUDIT.md`, `IOS_MACOS_INDEX.md`.
- Per-feature specs/plans: `plans/ios-macos/2026-06-2*-*-{design,plan}.md`.
