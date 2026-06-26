# Extract the simulator demo seed into its own file

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** Move `FinchStore.seedSimulatorDemo` (the ~200-line simulator-only demo data) into a new `SimulatorDemoSeed.swift`, so removing the dummy data later is "delete one file + one line." Pure refactor — no behavior change.

## Problem

The demo/dummy data lives as a `private func seedSimulatorDemo(_:)` inside the large
`FinchStore.swift` (lines 142–345). It's hard to find and would be fiddly to excise later
(it's tangled in among real store logic).

## Design

Pure extraction — the method is self-contained (uses only its local `apply`/`monthStart`
helpers + `Apply`/`Args`/`JSONValue`/`DatabaseQueue` from FinchCore; **0 `self`/store
references**), so it moves verbatim.

### New file: `ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift`

```swift
import Foundation
import FinchCore

/// Simulator-only demo data — a Personal/USD ledger with accounts (+groups),
/// categories, budgets (+groups), and ~2 months of transactions. NOT shipped to real
/// users: the call site in `FinchStore.bootstrap()` is gated by
/// `#if targetEnvironment(simulator)`.
///
/// To remove the demo entirely: delete this file and the `SimulatorDemoSeed.seed(...)`
/// line in FinchStore.swift (real devices already fall back to `seedMinimalStarter`).
enum SimulatorDemoSeed {
    static func seed(_ q: DatabaseQueue) throws {
        // ← verbatim body of the former seedSimulatorDemo (FinchStore.swift:143–344)
    }
}
```

### `FinchStore.swift`

- **Delete** the `private func seedSimulatorDemo(_ q: DatabaseQueue) throws { … }` method
  (lines 142–345).
- **Update the call** in `bootstrap()` (line 104):
  ```swift
  do { try SimulatorDemoSeed.seed(live) } catch { try? seedMinimalStarter(live) }
  ```
  (`#if targetEnvironment(simulator)` gate and the `seedMinimalStarter` fallback are
  unchanged.)

`import FinchCore` already exists in FinchStore; the new file imports it for the same
types. New file → `xcodegen generate`.

## Out of scope
- Any change to the seed *data* or behavior. `seedMinimalStarter` (real-user starter) —
  unchanged. No engine change.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) — proves the move compiles + the new file
  is in the target.
- **Manual (sim):** fresh re-seed (uninstall→reinstall) → the demo still loads (accounts,
  the Essentials/Lifestyle budget groups, transactions) — identical to before.

## Notes
- Collision: `FinchStore.swift` is the other stream's recently-active file (#378/#381/#382),
  though their current worktree is on the Ledger. Re-check `gh pr list` + that
  `FinchStore.swift` hasn't moved on origin right before pushing. PR → `feat/frontend`.
