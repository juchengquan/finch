# macOS parity roadmap

**Date:** 2026-06-27
**Status:** Roadmap (design). Phase 1 proceeds to an implementation plan next.
**Supersedes:** the macOS-specific portions of `IOS_MACOS_UI_GAP_AUDIT.md` / `IOS_MACOS_UI_REMEDIATION_PLAN.md` (2026-06-14), whose "Tier 1" feature gaps are now shipped (see Premise).

## Premise (verified 2026-06-27)

FinchMac builds from the **same `Sources/FinchApp`** as iOS, with an adaptive shell
(`AdaptiveShell` → sidebar + 3-column `MasterDetailShell` at regular width). Because the UI
is shared, **feature CRUD is already at parity** — spot-checked against current code:

- ✅ Account CRUD (`AccountSheet`, `AccountManagementViews`, `AccountDetailView`)
- ✅ Budget edit + cycle (`BudgetSheet(budget:)`, `updateBudget`/`updateBudgetCycle`)
- ✅ Scheduled edit (`ScheduledSheet(template:)`)
- ✅ Display-currency picker (`setDisplayCurrency`, per-ledger)
- ✅ Transaction splits + tags (`setTransactionTags`, splits in `EditTransactionSheet`)

So the remaining gap is **not features — it's macOS interaction & platform conventions**:
things that are touch-only or iOS-only and therefore degraded/unreachable on a Mac.

## The macOS-specific gaps (evidence)

- **Touch-only row actions.** **20 `swipeActions` vs 11 `contextMenu`** app-wide. Swipe is
  iOS-only, so any row whose actions live *only* in a swipe is **unreachable with a mouse**.
  Files with swipe-but-no-context: `PowerTools/RulesManagerView`, `WriteScreens/LedgerManagementView`,
  `WriteScreens/HoldingsView`, `WriteScreens/EditTransactionSheet`, `PowerTools/TagAdminView`,
  `PowerTools/ExchangeRatesView`, `PowerTools/CategoryAdminView`, `Common/GroupAdminView`; partial:
  `WriteScreens/AccountDetailView` (2 sw/1 ctx), `Tabs/ScheduledTab` (2 sw/1 ctx).
- **Multi-select bulk toolbar mislaid.** `ActivityTab.swift:206` uses
  `ToolbarItemGroup(placement: .bottomBar)` — shimmed to `.automatic` on macOS, so the
  selection actions land in an odd spot.
- **No keyboard list navigation** — no ↑/↓ move, ↵ open, or ⌫ delete on lists.
- **Attachment picking is iOS-only** — `PhotosPickerItem` (no `NSOpenPanel` path on macOS), so
  receipts can't be added on a Mac.
- **Menu/window conventions** — Settings is an in-app tab (not a ⌘, Preferences window); menu
  bar has ⌘N/⌘K/⌘1–6 only (no per-screen actions).
- **macOS has no Widgets / Spotlight / Share** (iOS-only extensions).

## Phased plan

Each phase is independently shippable and verified by a FinchMac (macOS) build + manual pass.

### Phase 1 — Interaction parity *(next; highest value, lowest risk)*
Give every swipe-only row a **right-click `.contextMenu`** with the same actions (Delete /
Edit / Confirm / Post / etc.), so all row actions are mouse-reachable on macOS. Scope = the
~10 files above. Also fix the **multi-select toolbar**: move the macOS bulk-action controls off
`.bottomBar` into a sensible placement (e.g. `.automatic`/principal or an inline bar).
*No engine change; additive `.contextMenu` blocks mirroring existing swipe buttons.*

### Phase 2 — Input & attachments
- macOS receipt picker: an `NSOpenPanel`-backed path in `AttachmentWriter` (behind the existing
  `#if os(iOS)` PhotosUI), so attachments work on Mac.
- Audit decimal/text-input affordances now that `.keyboardType` is a no-op on macOS (ensure
  every amount field accepts/validates typed decimals — `DecimalInput` already locale-aware).

### Phase 3 — Menu & window conventions
- **Settings → Preferences window** (`Settings` scene, ⌘,) on macOS instead of an in-app tab.
- **Richer menu bar** (`FinchCommands`): per-screen actions (New in current section, Export,
  Reconcile, Toggle sidebar groups) + a Help menu noting Mac gestures.
- **Keyboard list nav:** ↑/↓ selection, ↵ to open, ⌫ to delete on the primary lists.

### Phase 4 — macOS platform extensions *(heavy; optional, last)*
- A **macOS widget** target (reuse `FinchWidget` timeline/provider where possible).
- Spotlight indexing on macOS; evaluate a macOS share path. *(Large; may be split further.)*

## Out of scope
- Apple Watch (separate target). Re-architecting the shared shell. Any engine change.

## Testing (every phase)
- **Build:** FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`.
- **Manual (macOS):** run FinchMac, exercise the phase's surfaces with mouse + keyboard.

## Notes
- Sequencing rationale: Phase 1 closes the most-felt gap (unreachable actions) with the least
  risk (additive context menus), so it ships first. 2–4 escalate in effort and platform depth.
- Collision: phases touch shared tab/writescreen files (actively edited) — each phase re-checks
  `gh pr list` and keeps diffs additive. PRs → `feat/frontend`.
