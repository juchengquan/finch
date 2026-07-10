# iOS/macOS handoff & sync-up

**Date:** 2026-06-25 (status refreshed 2026-07-10)
**Branch context:** all work targets `feat/frontend`. Snapshot taken @ `a9945a8` (#419 merged). **All web→iOS parity gaps (Tier-1/2/3) are closed; the "deepen widgets" sub-project, macOS-parity Phases 1–4, and the full Watch sub-project (CP1 transport/glance · CP2 complication · CP3 on-wrist quick-add) are also complete.**
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
- **Ledger/Scheduled UI cleanup:** removed the net-worth **sparkline** from the Ledger header (#379); **Ledger tab → lean overview** (switcher · net worth · this-month) + a "View all activity" row that pushes the feed — feed also reachable from the Accounts summary (#380); **colored Scheduled type icons** (income green / transfer blue / expense red, #384); **fixed a FinchMac build break** — guarded `ScheduledCalendarView`'s `.pickerStyle(.wheel)` (iOS-only) with `#if os(iOS)` (#385). *(Lesson: #382/#383 merged with a red/unrun macOS check — let the iOS + macOS CI job go green before merging so a macOS-only break doesn't reach the base.)*
- **Other session (recent):** demo-seed budget groups (#381), scheduled calendar + search & redesign (#382/#383), grouped demo-seed accounts + demo-seed extracted to its own file (#387).
- **Native surfaces — "deepen widgets" sub-project (complete):** CP1 lock-screen / accessory families (#364) · CP2 configurable **Account + Budget** widgets (snapshot expansion + `AppIntentConfiguration`, #369) · CP3 interactive **quick-add** (`finch://add` scheme + `onOpenURL` + `.widgetURL`, #374). (Pre-existing scaffolds App Intents/Siri, Spotlight, Share extension, basic Watch glance remain as-is.)
- **Other session (recent):** recurring-charge detector (#359), flat dated activity feed (#368), confirm-transaction deletes + Ledger overflow menu (#370), budget-cycle edit folded into the edit sheet, gitignore (#366).
- **Full zh-Hans localization:** tab titles (#346) → **catalog refresh** capturing +131 stale keys (#349) → **the 96 remaining strings + nav-title bypass fix** (#350). Catalog 456 keys / 441 translated; 15 intentional format tokens. *(The ~97 #350 strings are AI-authored — native review advised before release.)*
- **Since the last snapshot (#387 → #401):**
  - *This session:* optional opening-balance row via a Settings toggle (#389); tightened Add-transaction title spacing (#392); confirm-before-delete on the ledger list (#395); **Settings ↔ Ledger nav swap** — Settings is now a bottom-bar tab, the two-layer Ledger is reached from the top-left `books.vertical` corner control, app launches on Accounts (spec/plan #398, impl #400, via superpowers subagent-driven dev). Plus a local-only (gitignored `.claude/skills/`) **ios-build-launch** skill capturing the build/run/test workflow.
  - *Other session:* **macOS parity Phases 1–3 — now complete:** context-menu coverage + multi-select toolbar (#396), file/PDF receipt picker via `.fileImporter` (#397), Preferences window + menu bar (Export/Help) + ⌫-delete (#399), wrap-up doc confirming Spotlight is already cross-platform + widgets are signing-gated (#401). Also: two-layer Ledger tab list→detail (#394), richer demo data (#393), ungrouped accounts/budgets render bare (#390), credit cards counted in net worth/liabilities by default (#391).
- **Since #401 → #419** (details live in the backlog table below; this is the merge record):
  - *This session:* **Insights Ring/StackedBar wiring** — savings-rate ring + net-worth-by-type allocation bar (spec #404, plan #405, impl #406, subagent-driven); Watch CP1 spec/plan (#408/#410, implemented by the other session in #412).
  - *Other session:* macOS ↵-open on Scheduled/Activity (#403) · feed date de-dup (#407) · backlog-reconcile doc (#409) · **what-if sliders** — interactive category-cut hypotheticals on Insights (#411) · **Watch CP1 bundle** — WCSession transport + live glance, widget account pre-fill, advice CP2, top-merchants card (#412) · **iPad multi-column** — Ledger in the 3-column shell (#414, spec/plan `2026-07-07-ipad-multicolumn-*`) · **Watch CP2** complication (#415, spec/plan #413) · **privacy mode** — one-tap mask for every rendered amount (#416) · **monthly-report PDF + Settings CSV export + Watch quick-add templates** (#417) · **Watch CP3 composer** — crown quick-add from a snapshot-borne catalog (#419, spec/plan #418). **The Watch sub-project is complete.**
- Docs/infra: parity inventory (#303, refreshed #343) + backlog reconcile (#313, re-reconciled #409) + this handoff (#315/#324/#388/#402); CI cache+skip (#276/#278).

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
| **Watch: complication + on-wrist quick-add** | M | ✅ Done — CP1 #412 (WCSession transport + live glance; spec #408, plan #410) · CP2 #415 (`FinchWatchComplication`, 4 accessory families + reload-on-push; spec/plan #413) · quick-add **templates** #417 (repeat-last from the glance; design record `2026-07-07-watch-quickadd-templates-design.md`) · **CP3 composer** #419 (crown amount + category chips from a snapshot-borne catalog; posts pending with staleness fallbacks + tap-date booking; spec/plan `2026-07-07-watch-cp3-*.md` #418, post-#417 addendum). **Watch sub-project complete** |
| Widget **account pre-fill** for quick-add (`finch://add?account=<id>`) | S | ✅ Done (#412) — Account widget's tap URL carries its account; `DeepLinkRouter` parses it into `pendingAddAccountId` → `AddTransactionSheet(defaultAccountId:)` |
| **Insights advice CP2** (5 day-of-week/day-of-month pattern rules) | S | ✅ Done (#412) — the 5 pattern rules ported into `generateInsights` in web priority order, web-matching gates/copy; +5 tests |
| **Receipt scanning** (VisionKit) | M | open — *device-only* (no sim camera) |
| **Insights/analytics expansion** (spend-by-merchant, net-worth-over-time) | M | ✅ Done — `Ring`/`StackedBar` wired in #406 (savings-rate ring, net-worth-by-type bar; net-worth-over-time was already `NetWorthCard`); **spend-by-merchant** card + `topMerchants` selector (#412) |
| **CloudKit sync maturity** | L | open (iOS-ahead scaffold; needs container provisioning + multi-device testing) |
| **macOS desktop parity (Phases 1–4)** | M | ✅ Done (#396/#397/#399/#401/#403) — context menus, multi-select toolbar, `.fileImporter` receipts, Preferences window, menu bar (Export/Help), ⌫-delete, **⌫-select + ↵-open** on Scheduled/Activity; Spotlight already cross-platform; **widget = signing-gated** (team-only App Group — needs a paid Dev Team) |
| **Feed date de-dup** (date shown only when it changes) | S | ✅ Done (#407) |
| **iPad multi-column** | M | 🟡 Ledger joins the 3-column shell + split column widths (#414; spec/plan `2026-07-07-ipad-multicolumn-*.md`). Deferred there: Activity/Scheduled detail columns (need net-new inline detail views) and sidebar-collapse persistence (rotation auto-collapse caveat) |
| **PDF/CSV export** | M | ✅ Done (#417; spec/plan `2026-07-07-ios-export-report-*.md`) — one-page monthly report PDF (`ImageRenderer`, print-styled) on Insights › Breakdown + a Face-ID-gated full-history CSV row in Settings. CSV builder (`TxExport`) + month-scoped Breakdown CSV already existed. **Tax export stays open** — follows the web `is_tax_relevant` schema feature (FEATURE_IDEAS §8.1) |
| **Polish themes** (not formally specced) | — | open — accessibility pass (VoiceOver/Dynamic Type/contrast). |

**Verified already-shipped (2026-06-28 — were mistakenly carried as "deferred" from old plan scope-notes; do NOT re-chase):**
- **Edit-transaction currency + counterparty** — `EditTransactionSheet` already has the currency `Picker` (saved via `patch["currency"]`) and counterparty typeahead + **"Create "<name>""** (runs `createCounterparty` then links).
- **Rules multi-condition / multi-action builder** — `RuleSheet` already does all/any multi-condition + multi-action create/edit. Only *advanced* constructs (nested groups / NOT / CP2 fields / split) open read-only.
- **Tags + status on transfers** — the Add sheet shows the Status + Tags pickers for transfers (`if kind != .adjust`) and the save passes `status` + `tagIds` to `createTransfer`. *Truly* remaining (both niche, low value): **receipt-on-transfer** (Receipt section is line-item-only) and **tags/status on adjust-balance** (Reconcile hardcodes confirmed, no tags).

**Not gaps (don't add back):** Goals = income budgets by design; "saved filter presets" = Activity saved searches (done #333).

## Collision avoidance

- 0 open PRs at this snapshot (@`a9945a8`). Both sessions push frequently — **`git fetch` + re-read the inventory/this doc before picking**, and check `gh pr list --base feat/frontend --state open` (inspect the PR's *files*, not just the title).
- **All parity is done — only the iOS-original backlog remains, so coordinate per-feature.** Recent division of labour:
  - *Other session:* Insights/charts + Settings/theme/i18n + notifications (through #350); **macOS parity Phases 1–4 (#396–#401, #403)**, two-layer Ledger (#394), demo/net-worth tweaks (#390–#393); recently **the whole Watch implementation (#412/#415/#417/#419)**, what-if sliders (#411), iPad multi-column (#414), privacy mode (#416), PDF/CSV export (#417), feed de-dup (#407).
  - *This session:* accounts/reconcile (#329, #355/#358), budgets per-account (#337), saved searches (#333), opening-balance (#347/#389), **widgets sub-project CP1/2/3 (#364/#369/#374)** + the `finch://` scheme, Ledger/Scheduled UI cleanup (#379/#380/#384/#385), title spacing (#392), ledger-delete confirm (#395), **Settings ↔ Ledger nav swap (#398/#400)**, **Insights Ring/StackedBar wiring (#404–#406)**, **Watch CP1 spec/plan (#408/#410)**.
- **Hot/shared files — check before editing:** `Tabs/ActivityTab.swift`, `WriteScreens/TransactionFilterSheet.swift`, `WriteScreens/EditTransactionSheet.swift`, `WriteScreens/AccountDetailView.swift`, `WriteScreens/BudgetSheet.swift`, `Tabs/SettingsTab.swift`, `Project/Projections+State.swift`, `Selectors/Selectors.swift`, `Common/ChartViews/*`.
- **Avoid right now (other session active):** the **Watch targets** (`FinchWatch*`, `PhoneWatchLink`, `WatchSnapshotPayload`) and Insights (what-if sliders, privacy mode touched every rendered amount) — they just shipped #411–#419 there; also the iPad/macOS shell (`AdaptiveShell`/`SplitViewShell`/`MasterDetailShell`) reworked again for iPad multi-column (#414). `git fetch` + check open PRs before editing shared shell/Settings/Insights files. **Clear for this session (the only open items):** **receipt scanning** (VisionKit, device-only), **CloudKit sync maturity**, the **a11y pass** (VoiceOver/Dynamic Type/contrast), **tax export** (follows web `is_tax_relevant`, FEATURE_IDEAS §8.1), and the iPad deferrals from #414 (Activity/Scheduled detail columns, sidebar-collapse persistence). `finch://` + `DeepLinkRouter.handle` remain the deep-link entry point.

## Pointers

- Source of truth for gaps: `2026-06-25-ios-web-parity-gap-inventory.md` (refreshed @`db6ab1c`, #343).
- Roadmap / audit: `IOS_MACOS_ROADMAP.md`, `IOS_MACOS_UI_GAP_AUDIT.md`, `IOS_MACOS_INDEX.md`.
- Per-feature specs/plans: `plans/ios-macos/2026-06-2*-*-{design,plan}.md`.
