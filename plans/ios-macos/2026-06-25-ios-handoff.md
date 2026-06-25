# iOS/macOS handoff & sync-up

**Date:** 2026-06-25 (status bumped 2026-06-26)
**Branch context:** all work targets `feat/frontend`. Snapshot taken @ `20554f2` (#323 merged).
**Purpose:** one page to sync between work sessions — what shipped, what's left, how we work, and how to avoid collisions. Pairs with the verified [parity-gap inventory](2026-06-25-ios-web-parity-gap-inventory.md) (the source of truth for web↔iOS gaps).

## How we work (conventions)

- **Flow per feature:** brainstorm → design spec → implementation plan → subagent-driven execution (one subagent per task, review between) → PR to `feat/frontend` → user merges → delete worktree/branch. Specs/plans live in `plans/ios-macos/<date>-<feature>-{design,plan}.md`.
- **Worktrees:** each feature in its own `git worktree` off `origin/feat/frontend` (e.g. `/tmp/finch-<slug>`); the user edits concurrently, so never stash/checkout in the main tree.
- **Commits:** **no `Co-Authored-By` trailer**. **Builds:** always FinchApp (iOS) **and** FinchMac (macOS); `xcodegen generate` after adding/removing files. **Engine tests:** `cd ios/FinchCore && swift test` — keep **ParityTests** green (additive selectors are safe; note `ListOptions` is decoded by the parity fixtures, so new non-optional fields need Codable defaults).
- **CI:** docs-only PRs (`plans/**`, `*.md`) skip CI via `paths-ignore` (#278). iOS CI was ~halved (#276).
- **Sim verification caveat:** **SwiftUI sheets/menus do not open under AppleScript AX automation** — the feed filter sheet (#286/#308/#314) and toolbar **Menu** popovers (#321) both register the press but don't present (menu items live in a separate AX window), and the Settings **gear** button doesn't navigate (#248/#306), which blocks any Settings-deep path (Power Tools, merchant detail). Verify those by hand, or lean on engine unit tests for the logic. Seed DB state + AXPress by accessibility description where possible; tappable rows/buttons on a visible screen do work.

## Shipped since the parity snapshot (@9406714)

**Web→iOS parity catch-up (Tier-1/2 from the inventory — now CLOSED):**
- Scheduled **calendar view** (#307) · Budgets **rollover UI** (#311) · **FX source + currency picker** (#302) · **Rules** builder CP2a/CP2b — rules parity complete (#292, #297) · **Insights advice engine** CP1, core 6 rules (#323) — **Tier-1 now fully closed**.

**iOS-original UX:**
- Edit-form parity with Add: status/account/refund-link (#283), currency (#296), counterparty suggestions (#312); **kind reclassification** in Edit (#319).
- Feed: result count + no-results + bulk confirm/delete (#293), filter by merchant (#308), **multi-tag filter Any/All (#314)**, **sort options** date/amount (#321).
- Rows: refund badge (#298), tag colors (#301).
- In-app receipt preview / Quick Look (#289); merchant detail screen (#306) + **deep-link to filtered feed** (#318).
- Docs: parity inventory (#303) + backlog reconcile (#313) + this handoff (#315). Infra: CI cache+skip (#276/#278).

## Remaining web→iOS parity gaps

See the inventory for detail. **All Tier-1 gaps are now closed** (Scheduled calendar, Budget rollover, Rules, FX, and Insights advice engine #323). Remaining are Tier-2/3 (Med/Low):
- **Tier-2/3:** accounts reconcile-status badge / quick-add-during-reconcile / pending-vs-confirmed split; budgets per-account filter; Insights `Ring`/`StackedBar` primitives; settings theme + locale; opening-balance display. Plus the inventory's Tier-2 **Activity: saved searches** (= "saved filter presets").

## iOS-original enhancement backlog (not parity)

Tracked here + in the inventory. Status as of this snapshot:

| Item | Size | Status |
|---|---|---|
| Multi-tag filter (Any/All) | S | ✅ Done (#314) |
| Feed **sort options** (amount / oldest-first) | S | ✅ Done (#321) |
| **Merchant detail → pre-filtered feed** deep-link | S | ✅ Done (#318) |
| **Kind reclassification** in Edit (leg rebuild) | M | ✅ Done (#319) |
| Receipt **thumbnails** in the Edit list | S | open |
| Preview a receipt **from a transaction row** | S | open (preview is Edit-only, #289) |
| **Receipt scanning** (VisionKit) | M | open |
| **Insights/analytics expansion** (spend-by-merchant, net-worth-over-time) | M | open — core advice engine landed (#323); these specific reports remain |
| **Notifications** end-to-end verification | M | open |
| **CloudKit sync maturity** | L | open (iOS-ahead scaffold; needs container provisioning + multi-device testing) |

**Not gaps (don't add back):** Goals = income budgets by design; "saved filter presets" = the inventory's Tier-2 *Activity: saved searches*.

## Collision avoidance

- No open PRs at this snapshot (@`20554f2`). Both sessions push frequently — **`git fetch` + re-read the inventory/this doc before picking**, and check `gh pr list --base feat/frontend --state open`.
- The other session drove the **parity tiers** (Scheduled/Budgets/FX/Rules/Insights — now all closed) and has also picked up backlog items (kind reclassification #319); this session drove the **iOS-original backlog** (feed/rows/merchant/Edit polish). With Tier-1 done, **the two streams now overlap more — coordinate on the remaining backlog** to avoid double-work. Hot files: `ActivityTab.swift`, `TransactionFilterSheet.swift`, `EditTransactionSheet.swift`, `Selectors.swift`.

## Pointers

- Source of truth for gaps: `2026-06-25-ios-web-parity-gap-inventory.md`.
- Roadmap / audit: `IOS_MACOS_ROADMAP.md`, `IOS_MACOS_UI_GAP_AUDIT.md`, `IOS_MACOS_INDEX.md`.
- Per-feature specs/plans: `plans/ios-macos/2026-06-25-*-{design,plan}.md`.
