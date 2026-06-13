# Phases 3–8 — open questions parked during implementation

Continuing "all the rest" (3, 4, 5, 6.5, 7, 8). Same rule as the 6.x batch: park
genuine product/scope questions with the default I chose, reconcile at the end.

Many of these phases have **device-infrastructure** parts that cannot be built or
verified in the headless simulator CI (extra Xcode targets, App Group / iCloud /
CloudKit entitlements, notarization, real Watch/Widget hosts). For those I
implement the **CI-verifiable core** and document the deferred infra here rather
than risk a red build or claim false completion.

> Status legend: ⏳ open · ✅ resolved · 🔧 deferred-infra (built code, infra TODO)

## Phase 3 — Adaptive iPad / macOS

- ✅ **Shell adaptation.** Implemented: `AdaptiveShell` switches on
  `horizontalSizeClass` — iPhone/compact keeps the bottom tab bar; iPad/Mac
  regular width gets a `NavigationSplitView` sidebar + detail. Built for both the
  iPhone and iPad simulators.
- 🔧 **macOS distribution target.** The Mac App Store + notarised direct-download
  targets need signing/provisioning/notarization — not headless-CI-verifiable.
  The adaptive shell is Mac-ready (size-class + NavigationSplitView), but the
  separate Mac target + menu bar + the two distribution pipelines are deferred
  infra.
- ⏳ **Multi-window / per-window ledger.** The design proposes one window per
  ledger with a per-window `activeLedgerId`. **Default chosen:** keep
  `FinchStore` a singleton with a single shared `activeLedgerId` (no per-window
  ledger) — multi-window would require de-singletoning the store, a large change.
  Revisit if per-window ledgers are wanted.
- ⏳ **⌘K command palette / full keyboard-shortcut set.** Added basic tab
  shortcuts; the full Mac ⌘K palette + menu commands are deferred with the Mac
  target.
