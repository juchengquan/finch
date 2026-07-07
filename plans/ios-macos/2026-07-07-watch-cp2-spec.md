# Spec: Watch sub-project CP2 — watch-face complication

**Date:** 2026-07-07
**Status:** design approved, ready for implementation plan
**Scope:** native watchOS (`ios/`). Second checkpoint of the Watch sub-project. CP1 (#412) built the WCSession transport + live glance; CP3 (on-wrist quick-add) stays deferred to its own spec.

## Goal

Put finch on the watch face: a WidgetKit **accessory complication** (circular · corner · inline · rectangular) that renders the same snapshot the glance shows — budget-used gauge, net worth, weekly spend — and refreshes whenever the phone pushes a new snapshot over the CP1 transport.

## Motivation

- The glance requires opening the app; the complication is the always-visible surface — the single highest-frequency touchpoint Apple platforms offer.
- CP1 deliberately built the plumbing this needs: the snapshot now lives in the **watch's own** App Group (`group.com.juchengquan.finch`, key `watchSnapshot`), written by `WatchSnapshotStore` on every received context. A complication extension on the watch can read that container directly — no new transport work.
- Tapping the complication launches the watch app (WidgetKit default) — the glance is the natural landing.

## Current state (baseline, @ #412)

- `ios/FinchWatch/FinchWatchApp.swift` — standalone watchOS app (`com.juchengquan.finch.watch`, **no FinchCore dep**): `WatchSnapshotStore` (WCSession receive → persist Data to the watch App Group → publish, stale-drop by `generatedAt`) + `GlanceView` + `@main`. Entitlement: App Group `group.com.juchengquan.finch`.
- `ios/Shared/WatchSnapshotPayload.swift` — Foundation-only wire format (`netWorth`, `currency`, `budgetUsedPct`, `weeklySpent`, `generatedAt`), compiled into both `FinchApp` and `FinchWatch`.
- `ios/FinchWidget/FinchWidget.swift` — the **iOS** widget already renders `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` from its snapshot; its layouts are the visual reference to mirror (it is an iOS target and cannot serve watch faces).
- `ios/project.yml` — `FinchWidget` shows the app-extension recipe to copy (type `app-extension`, `NSExtensionPointIdentifier com.apple.widgetkit-extension`, `CODE_SIGNING_ALLOWED: NO`).
- There is **no widget/complication target for watchOS** yet.

## Design

### 1. New target — `FinchWatchComplication`

- watchOS **WidgetKit extension** embedded in the watch app:
  - `type: app-extension`, `platform: watchOS`, sources `ios/FinchWatchComplication/` + `ios/Shared/` (payload + display helpers; **no FinchCore**, keeping the whole watch stack engine-free).
  - `PRODUCT_BUNDLE_IDENTIFIER: com.juchengquan.finch.watch.complication` (must be prefixed by the watch app's id).
  - `FinchWatch` gains `dependencies: [target: FinchWatchComplication]` so the extension is embedded; new scheme entry not required (builds via FinchWatch).
  - Info.plist mirrors `FinchWidget/Info.plist` (`NSExtensionPointIdentifier: com.apple.widgetkit-extension`); entitlements = the same App Group as the watch app. `CODE_SIGNING_ALLOWED: NO` (simulator-only, same as every target).
- `xcodegen generate` after the `project.yml` edit.

### 2. Data path — read the watch App Group, reload on push

- The extension reads `UserDefaults(suiteName: "group.com.juchengquan.finch").data(forKey: "watchSnapshot")` → `WatchSnapshotPayload.decode` — exactly the store's persistence, shared constants (see §3).
- **Refresh trigger:** `WatchSnapshotStore.session(_:didReceiveApplicationContext:)` adds `WidgetCenter.shared.reloadAllTimelines()` after persisting (import WidgetKit — available on watchOS). So the complication updates within the same wake that delivers a new snapshot.
- **Timeline:** single entry, `policy: .after(now + 3600)` — mirrors `FinchProvider`. The hourly poll is a safety net; the reload call is the real freshness path.

### 3. Shared constants + display helpers — `WatchSnapshotPayload+Display.swift`

New Foundation-only file in `ios/Shared/` (compiled into FinchApp, FinchWatch, and the new extension):

- `enum WatchStore { static let suite = "group.com.juchengquan.finch"; static let key = "watchSnapshot" }` — today the suite/key literals are duplicated in `WatchSnapshotStore`; the store and the extension both switch to these.
- `extension WatchSnapshotPayload`:
  - `func shortMoney(_ amount: Double) -> String` — compact currency for tiny faces (`$12.3k`, `¥1.2M`; `maximumFractionDigits` 1 above 1k, 0 below), used by corner labels + rectangular rows. (The glance's full formatter stays as is.)
  - `var isStale: Bool` — `generatedAt` older than **24 h**. Stale complications render dimmed (`.secondary`) rather than hiding — old data beats no data on a watch face.
- Pure Foundation → unit-testable from `FinchAppTests` (the established CP1 pattern — watch code itself has no test target).

### 4. Families & layouts (mirror `FinchWidgetView`'s accessory cases)

| Family | Content |
|---|---|
| `.accessoryCircular` | Budget gauge (`.gaugeStyle(.accessoryCircular)`), current value `\(pct)` |
| `.accessoryCorner` | Budget gauge + `.widgetLabel { Text(net worth, shortMoney) }` (watch-only family) |
| `.accessoryInline` | `finch · {net worth}` |
| `.accessoryRectangular` | Net worth headline + `Budget {pct}% · Wk {weekly}` caption (shortMoney) |

- `supportedFamilies: [.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular]`.
- No-snapshot placeholder: em-dash values (`—`) so the face never shows garbage; `placeholder(in:)` returns the same.
- Stale (`isStale`): apply `.foregroundStyle(.secondary)` to the value texts (gauge stays readable).
- `containerBackground(.clear, for: .widget)` on accessory families (matches FinchWidget).

### 5. Out of scope (explicitly)

- **CP3 — on-wrist quick-add** (reverse WCSession direction + `finch://` routes) — own spec.
- Live Activities / Smart Stack relevance, `AppIntentConfiguration` (account/budget pickers) on the watch — the iOS widget has them; the watch complication ships fixed-content first.
- Complication tap deep-routing (tap opens the watch app's single glance — nothing to route).
- Any FinchCore dependency on watchOS.

## Verification

- `xcodebuild build` for **FinchWatch** (`-destination 'generic/platform=watchOS Simulator'`) now also builds + embeds the extension; **FinchApp** (iOS sim) and **FinchMac** (macOS, `CODE_SIGNING_ALLOWED=NO`) stay green (Shared file additions compile everywhere — keep them Foundation-only).
- `FinchAppTests`: round-trip already covered (CP1); new tests for `shortMoney` thresholds/rounding + `isStale` boundary.
- **By hand in the watchOS simulator** (AX automation can't edit watch faces): long-press face → add the finch complication in each family → confirm placeholder → run the paired iPhone app, mutate data → confirm the complication updates after the context delivery (may need a face wake). Screenshot for the PR.
