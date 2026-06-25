# iOS/macOS handoff & sync-up

**Date:** 2026-06-25
**Branch context:** all work targets `feat/frontend`. Snapshot taken @ `57ad564` (#314 merged).
**Purpose:** one page to sync between work sessions — what shipped, what's left, how we work, and how to avoid collisions. Pairs with the verified [parity-gap inventory](2026-06-25-ios-web-parity-gap-inventory.md) (the source of truth for web↔iOS gaps).

## How we work (conventions)

- **Flow per feature:** brainstorm → design spec → implementation plan → subagent-driven execution (one subagent per task, review between) → PR to `feat/frontend` → user merges → delete worktree/branch. Specs/plans live in `plans/ios-macos/<date>-<feature>-{design,plan}.md`.
- **Worktrees:** each feature in its own `git worktree` off `origin/feat/frontend` (e.g. `/tmp/finch-<slug>`); the user edits concurrently, so never stash/checkout in the main tree.
- **Commits:** **no `Co-Authored-By` trailer**. **Builds:** always FinchApp (iOS) **and** FinchMac (macOS); `xcodegen generate` after adding/removing files. **Engine tests:** `cd ios/FinchCore && swift test` — keep **ParityTests** green (additive selectors are safe; note `ListOptions` is decoded by the parity fixtures, so new non-optional fields need Codable defaults).
- **CI:** docs-only PRs (`plans/**`, `*.md`) skip CI via `paths-ignore` (#278). iOS CI was ~halved (#276).
- **Sim verification caveat:** the feed's **filter-sheet toolbar button does not open under AppleScript AX automation** (seen on #286/#308/#314) — verify filter-sheet UI by hand, or lean on engine unit tests for the logic. Toolbar/gear buttons (Settings) are likewise flaky; seed DB state + AXPress by accessibility description where possible.

## Shipped since the parity snapshot (@9406714)

**Web→iOS parity catch-up (Tier-1/2 from the inventory — now CLOSED):**
- Scheduled **calendar view** (#307) · Budgets **rollover UI** (#311) · **FX source + currency picker** (#302) · **Rules** builder CP2a/CP2b — rules parity complete (#292, #297).

**iOS-original UX (this session):**
- Edit-form parity with Add: status/account/refund-link (#283), currency (#296), counterparty suggestions (#312).
- Feed: result count + no-results + bulk confirm/delete (#293), filter by merchant (#308), **multi-tag filter Any/All (#314)**.
- Rows: refund badge (#298), tag colors (#301).
- In-app receipt preview / Quick Look (#289); merchant detail screen (#306).
- Docs: parity inventory (#303) + backlog reconcile (#313). Infra: CI cache+skip (#276/#278).

## Remaining web→iOS parity gaps

See the inventory for detail. After the Tier-1 closures above, the notable open one is:
- **Tier-1: Insights advice/rules engine** — iOS Insights is chart-cards only; web runs ~6 narrative rules (`frontend/lib/insights.ts`). Port as `Selectors` + a card.
- **Tier-2/3:** accounts reconcile-status badge / quick-add-during-reconcile / pending-vs-confirmed split; budgets per-account filter; Insights `Ring`/`StackedBar` primitives; settings theme + locale; opening-balance display. (All Med/Low.)

## iOS-original enhancement backlog (not parity)

Tracked here + in the inventory. Status as of this snapshot:

| Item | Size | Status |
|---|---|---|
| Multi-tag filter (Any/All) | S | ✅ Done (#314) |
| Feed **sort options** (amount / oldest-first) | S | open |
| Receipt **thumbnails** in the Edit list | S | open |
| Preview a receipt **from a transaction row** | S | open (preview is Edit-only, #289) |
| **Merchant detail → pre-filtered feed** deep-link | S | open (pairs with #306/#308) |
| **Kind reclassification** in Edit (leg rebuild) | M | open |
| **Receipt scanning** (VisionKit) | M | open |
| **Insights/analytics expansion** (spend-by-merchant, net-worth-over-time) | M | open *(overlaps Tier-1 Insights engine)* |
| **Notifications** end-to-end verification | M | open |
| **CloudKit sync maturity** | L | open (iOS-ahead scaffold; needs container provisioning + multi-device testing) |

**Not gaps (don't add back):** Goals = income budgets by design; "saved filter presets" = the inventory's Tier-2 *Activity: saved searches*.

## Collision avoidance

- No open PRs at this snapshot. Both sessions push frequently — **`git fetch` + re-read the inventory/this doc before picking**, and check `gh pr list --base feat/frontend --state open`.
- The other session has been driving the **parity tiers** (Scheduled/Budgets/FX/Rules/Insights); this session drives the **iOS-original backlog**. Keep that split to avoid overlapping files (esp. `ActivityTab.swift`, `TransactionFilterSheet.swift`, `Selectors.swift`).

## Pointers

- Source of truth for gaps: `2026-06-25-ios-web-parity-gap-inventory.md`.
- Roadmap / audit: `IOS_MACOS_ROADMAP.md`, `IOS_MACOS_UI_GAP_AUDIT.md`, `IOS_MACOS_INDEX.md`.
- Per-feature specs/plans: `plans/ios-macos/2026-06-25-*-{design,plan}.md`.
