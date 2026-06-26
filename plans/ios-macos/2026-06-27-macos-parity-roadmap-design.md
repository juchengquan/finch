# macOS parity roadmap

**Date:** 2026-06-27
**Status (updated 2026-06-27):** **Phases 1–3 shipped** (#396, #397, #399). **Spotlight** turned
out to be already cross-platform (see Phase 4). The **macOS widget is code-signing-gated** and
deferred — macOS parity is considered **done for everything buildable/verifiable without a paid
Apple Developer Team**.
- ✅ **Phase 1** — Interaction parity (context menus for swipe-only rows; multi-select toolbar). #396
- ✅ **Phase 2** — File/PDF receipt picker (`.fileImporter`). #397
- ✅ **Phase 3** — Menu & window conventions (Preferences window ⌘,, File▸Export, ⌫-delete). #399
- **Phase 4** (signing-gated) — Spotlight already works on macOS; widget deferred. See below.

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
- **macOS has no Widgets / Share** extensions. *(Correction: Spotlight is NOT iOS-only —
  `SpotlightIndexer` uses cross-platform `CoreSpotlight` with no `#if os` gate and already
  runs on FinchMac; see Phase 4.)*

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

### Phase 4 — macOS platform extensions *(code-signing-gated; deferred)*

Investigated 2026-06-27. Two parts, very different status:

- **Spotlight — already done.** `SpotlightIndexer` (`Spotlight/SpotlightIndexer.swift`) uses
  `CoreSpotlight` / `CSSearchableIndex` with **no `#if os` gate**, and is invoked unconditionally
  in `FinchApp.swift`. It compiles into FinchMac and the launch-time `indexAll` runs without
  crashing on macOS (verified — FinchMac builds, launches, stays up). No code needed. Full
  *system-search surfacing* of results depends on signed distribution (same gate as the widget).

- **macOS widget — deferred (needs a paid Apple Developer Team).** A `FinchMacWidget` extension
  would reuse ~95% of `FinchWidget` (the snapshot data-flow via `WidgetSnapshot` is engine-side
  and cross-platform). **Blocker:** the widget must share the App Group `group.com.juchengquan.finch`
  to read the snapshot, but `FinchMac.entitlements` **deliberately dropped the App Group** because
  it is a **team-only entitlement** — that omission is what allows team-less *ad-hoc local signing*.
  Restoring it requires a real Development Team and would break the local ad-hoc build; a macOS
  widget also can't be installed/verified without proper signing. So this is **out of reach in a
  team-less environment** and is parked until signing infrastructure exists.
  - When a Dev Team is available: restore the App Group in `FinchMac.entitlements`, add a
    `FinchMacWidget` `app-extension` target (`platform: macOS`, App Group entitlement, bundle
    `com.juchengquan.finch.mac.widget`), copy `FinchWidget.swift` with minor macOS sizing tweaks
    (lock-screen accessory families are iOS-only), embed it in FinchMac.
  - A macOS **Share** extension is similarly deferrable (lower value on Mac).

**Conclusion:** macOS parity is **complete for everything achievable with ad-hoc local signing**
(Phases 1–3 + Spotlight). The widget is the only remaining item and is gated on a paid Dev Team.

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
