# Spec: Watch sub-project CP1 — WCSession transport + working glance

**Date:** 2026-06-28
**Status:** design approved, ready for implementation plan
**Scope:** native watchOS + iOS (`ios/`). First checkpoint of the Watch sub-project. CP2 (complication) and CP3 (on-wrist quick-add) are deferred to their own specs.

## Goal

Make the watch glance show **real, current data** from the phone by establishing a `WCSession` (Watch Connectivity) phone→watch data path. Today the `FinchWatch` glance reads `UserDefaults(suiteName: group.com.juchengquan.finch)` directly — but App Groups do not span devices, so on a real device that container is empty and the glance is non-functional. CP1 fixes the transport.

## Motivation

- The watch is a standalone watchOS app (`com.juchengquan.finch.watch`, no `FinchCore` dependency). It cannot read the iPhone's App-Group container.
- There is **no `WCSession` anywhere** in the project yet.
- This transport is the foundation the later checkpoints reuse (CP2 complication reads the same watch-local snapshot; CP3 quick-add sends the reverse direction over the same session).

## Current state (baseline)

- `ios/FinchWatch/FinchWatchApp.swift`: a single-file watchOS app with a local `struct WatchSnapshot: Codable { netWorth: Double; currency: String; budgetUsedPct: Int; weeklySpent: Double }`, a `GlanceView` that decodes it from the watch App Group, and `@main FinchWatchApp`. Entitlement: App Group `group.com.juchengquan.finch`.
- Phone: `FinchCore.WidgetSnapshot` has `netWorth: Double`, `currency: String`, `budgetUsedPct: Int` (0…100), `weeklySpent: Double` (plus widget-only `accounts`/`budgets`). `FinchApp/Widgets/WidgetSnapshot.swift` `build(from: store)`; the phone writes it + calls `WidgetCenter.shared.reloadAllTimelines()` in `FinchStore.swift:162` and `FinchStore+ImportExport.swift:81`.
- `project.yml` targets: `FinchApp` (iOS app), `FinchWatch` (watchOS app), `FinchCore` (SwiftPM, **not** linked by FinchWatch).

## Design

### Transport choice

Use `WCSession.updateApplicationContext(_:)` for the phone→watch push. It is the correct API for "always reflect the latest state": it **coalesces** (a newer context replaces an unsent older one — no queue buildup), overwrites the previous value, and is delivered when the watch next wakes / becomes reachable. (`transferUserInfo` is a guaranteed FIFO queue — wrong shape here, can back up; raw App-Group sharing doesn't cross devices — the current bug.)

### 1. Shared wire format — `WatchSnapshotPayload`

- New file `ios/Shared/WatchSnapshotPayload.swift`, **Foundation only** (no `FinchCore`, no SwiftUI), added to the `sources` of **both** `FinchApp` and `FinchWatch` in `project.yml`. Keeps the watch dependency-free while guaranteeing both sides agree on the format.
- ```swift
  struct WatchSnapshotPayload: Codable, Equatable {
      var netWorth: Double
      var currency: String
      var budgetUsedPct: Int
      var weeklySpent: Double
      var generatedAt: Date
      func encoded() -> Data? { try? JSONEncoder().encode(self) }
      static func decode(_ data: Data) -> WatchSnapshotPayload? { try? JSONDecoder().decode(WatchSnapshotPayload.self, from: data) }
  }
  ```
- `generatedAt` lets the watch ignore an out-of-order/stale context and aids debugging.

### 2. Phone side — `PhoneWatchLink`

- New file `ios/FinchApp/Sources/FinchApp/Watch/PhoneWatchLink.swift`: `final class PhoneWatchLink: NSObject, WCSessionDelegate` (singleton `shared`).
  - `activate()`: if `WCSession.isSupported()`, set delegate + `activate()`. Called once from `FinchApp` `.task`.
  - `push(_ payload: WatchSnapshotPayload)`: guard `WCSession.isSupported()`, `session.activationState == .activated`, and (cheap inertness) `session.isPaired && session.isWatchAppInstalled`; then `try? session.updateApplicationContext(["snapshot": data])` where `data = payload.encoded()`.
  - Required delegate stubs: `session(_:activationDidCompleteWith:error:)` (no-op / on `.activated` push the latest once), and on iOS `sessionDidBecomeInactive(_:)` + `sessionDidDeactivate(_:)` (the latter re-activates: `WCSession.default.activate()` — supports watch switching).
- **Hook into the existing snapshot write:** wherever the phone writes the WidgetSnapshot + `reloadAllTimelines()` (`FinchStore`/`FinchStore+ImportExport`), also build a `WatchSnapshotPayload` from the same `WidgetSnapshot` (map the four fields + `generatedAt = Date()`) and call `PhoneWatchLink.shared.push(payload)`. Factor the build+push into one small helper called from both write sites (DRY).

### 3. Watch side — `WatchSnapshotStore`

- Refactor `FinchWatch/FinchWatchApp.swift`: remove the local `WatchSnapshot` struct; use the shared `WatchSnapshotPayload`.
- Add `final class WatchSnapshotStore: NSObject, ObservableObject, WCSessionDelegate`:
  - `@Published var snapshot: WatchSnapshotPayload?`.
  - On init: activate `WCSession` (if supported) and load the last-persisted payload from the watch's own `UserDefaults(suiteName: "group.com.juchengquan.finch")` (key `"watchSnapshot"`) so the glance shows last-known data immediately.
  - `session(_:didReceiveApplicationContext:)`: decode `context["snapshot"] as? Data` → on success, persist the Data to the watch App Group and set `snapshot` on the main actor (drop it if `generatedAt` is older than the current one).
  - `session(_:activationDidCompleteWith:error:)`: no-op (watchOS needs only this stub).
- `GlanceView` observes the store (`@StateObject`/`@ObservedObject`) and renders `store.snapshot` (same four fields + the existing `money(_:_:)` formatter). Empty state when `snapshot == nil`: a muted "Open finch on your iPhone" hint.
- `FinchWatchApp` owns the `WatchSnapshotStore` as a `@StateObject` and injects it into `GlanceView`.

## Non-goals

- No complication (CP2) and no on-wrist quick-add / reverse messaging (CP3).
- No new fields beyond the four the glance already shows (+ `generatedAt`).
- No change to the phone's widgets, the `WidgetSnapshot` type, or `FinchCore`.
- No CloudKit; transport is WCSession only.

## Testing / verification

- **Unit tests (`FinchAppTests`, TDD):**
  - `WatchSnapshotPayload` encode→decode round-trip returns an equal value.
  - Building a payload from a known `WidgetSnapshot` copies the four fields correctly (a small pure mapping helper, e.g. `WatchSnapshotPayload(from: WidgetSnapshot)` or the shared build helper).
- **Builds (all must pass):** `FinchApp` (iOS sim), `FinchMac` (macOS), **`FinchWatch` (watchOS sim)** — run `xcodegen generate` first (new shared file in two targets).
- **Live round-trip (best-effort / by-inspection):** on a *paired* iPhone+Watch simulator, a phone mutation should surface on the watch glance. This needs a paired-sim setup that may not be fully exercisable in the harness; the delegate wiring + the unit-tested payload are the primary guarantees. State clearly in the report whether the live path was exercised or inspected.

## Risks

- **Multi-target file inclusion:** adding `ios/Shared/WatchSnapshotPayload.swift` to both `FinchApp` and `FinchWatch` in `project.yml` then `xcodegen generate`; confirm both targets still build and don't double-compile elsewhere.
- **`WCSessionDelegate` platform differences:** the two delegates are separate classes in separate targets, so no `#if` is needed. `PhoneWatchLink` (FinchApp/iOS only) implements the iOS-required stubs — `activationDidCompleteWith`, `sessionDidBecomeInactive`, `sessionDidDeactivate`. `WatchSnapshotStore` (FinchWatch/watchOS only) implements just `activationDidCompleteWith` (the only one watchOS requires). The single *shared* file, `WatchSnapshotPayload.swift`, is Foundation-only with no platform APIs, so it compiles in both.
- **Inertness:** all phone pushes are guarded so phone-only users (no watch) see no behavior change and no errors.
- **watchOS build availability** in this harness — if a watchOS simulator/build isn't runnable, fall back to verifying FinchWatch compiles via the shared scheme and note the limitation.
