# Privacy Mode (one-tap amount mask) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port web #416's privacy mode to iOS/macOS — a one-tap toggle that masks every rendered amount as `••••`.

**Architecture:** A `@Published` UserDefaults-backed flag on `FinchStore` gates the store's display formatters (Task 1, TDD). The UI layer adds an eye toggle to all 5 primary tabs, a command-palette entry, and a macOS menu item, and routes the four direct `Money.format` view sites through a new mask-aware `displayNative` helper (Task 2, build + sim verified).

**Tech Stack:** Swift / SwiftUI, XcodeGen (`ios/`), XCTest (`FinchAppTests`). Spec: `plans/ios-macos/2026-07-12-privacy-mode-spec.md`.

## Global Constraints

- UserDefaults key is exactly **`finch.privacy`**; mask string is exactly **`"••••"`** (web's `MONEY_MASK`). Never persisted to the DB or `.finch` packs (UserDefaults only).
- Mask **formatted display strings only** — numeric helpers (`toBase`), selector math, chart geometry, percentages, input `TextField`s, `FinchCore.Money.format` (feeds CSV/PDF exports), and the split-editor validation error all stay real.
- No `FinchCore` changes; no widget/Watch/Spotlight/notification changes (in-app only).
- Build **both** `FinchApp` (iOS) and `FinchMac` (macOS). Keep toolbar placements consistent with neighboring `#if os(iOS)` guards (the eye button itself is cross-platform — not iOS-gated).
- Run from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` first in a fresh worktree. Sim commands per the `ios-build-launch` skill; if `name=iPhone 17 Pro Max` isn't found use a booted sim's `id=<udid>` (there's `finch-fresh-6`).

---

### Task 1: `FinchStore.privacyMode` + masked formatters (+ tests)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/FinchStore.swift` (class body, next to the `activeLedgerKey` pattern ~line 34)
- Modify: `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift` (formatters ~lines 100-107 and ~236-241; new `displayNative`)
- Test: `ios/FinchApp/Tests/FinchAppTests/PrivacyModeTests.swift` (create)

**Interfaces:**
- Produces (consumed by Task 2): `FinchStore.privacyMode: Bool` (`@Published`, get/set), `FinchStore.moneyMask` (`"••••"`), `FinchStore.privacyKey` (`"finch.privacy"`), and `func displayNative(_ amount: Double, currency: String) -> String` (mask-aware, no conversion).

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchApp/Tests/FinchAppTests/PrivacyModeTests.swift`:

```swift
import XCTest
@testable import FinchApp

@MainActor
final class PrivacyModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: FinchStore.privacyKey)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FinchStore.privacyKey)
        super.tearDown()
    }

    func test_offByDefault_formatsRealAmounts() {
        let store = FinchStore()
        XCTAssertFalse(store.privacyMode)
        XCTAssertNotEqual(store.displayMoneyBase(1234.5), FinchStore.moneyMask)
        XCTAssertTrue(store.displayMoneyBase(1234.5).contains("1"))
    }

    func test_on_masksAllDisplayFormatters() {
        let store = FinchStore()
        store.privacyMode = true
        XCTAssertEqual(store.displayMoneyBase(1234.5), FinchStore.moneyMask)
        XCTAssertEqual(store.displayMoney(99.0, from: "EUR"), FinchStore.moneyMask)
        XCTAssertEqual(store.displayNative(42.0, currency: "USD"), FinchStore.moneyMask)
    }

    func test_off_displayNativeFormatsInOwnCurrency() {
        let store = FinchStore()
        XCTAssertTrue(store.displayNative(42.0, currency: "USD").contains("42"))
    }

    func test_togglePersistsToUserDefaults_andNewStoreReadsIt() {
        let store = FinchStore()
        store.privacyMode = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: FinchStore.privacyKey))
        XCTAssertTrue(FinchStore().privacyMode)   // fresh store re-reads the flag
        store.privacyMode = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: FinchStore.privacyKey))
    }
}
```

- [ ] **Step 2: Run them to confirm they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/PrivacyModeTests 2>&1 | grep -iE "cannot find|error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL to compile — `privacyKey`/`privacyMode`/`moneyMask`/`displayNative` don't exist.

- [ ] **Step 3: Add the state to `FinchStore.swift`**

In the class body, right after the `activeLedgerKey` declaration block (before `@Published public var activeLedgerId`), add:

```swift
    /// Privacy mode — a per-device viewing preference that masks every rendered
    /// amount (web parity: #416). Mirrors the web's localStorage key name; lives
    /// in UserDefaults only — never the DB, never `.finch` exports.
    static let privacyKey = "finch.privacy"
    /// What every masked amount renders as (web's MONEY_MASK).
    public static let moneyMask = "••••"
    @Published public var privacyMode: Bool = UserDefaults.standard.bool(forKey: FinchStore.privacyKey) {
        didSet {
            guard oldValue != privacyMode else { return }
            UserDefaults.standard.set(privacyMode, forKey: FinchStore.privacyKey)
        }
    }
```

- [ ] **Step 4: Gate the formatters in `FinchStore+ViewHelpers.swift`**

Change `displayMoneyBase` (the mask propagates to `displayMoney(_:from:)`, `subtotalDisplay`, `netWorthDisplay`, which all delegate to it):

```swift
    /// ledger base → display. Returns the privacy mask when privacy mode is on
    /// (masking here propagates to displayMoney(_:from:)/subtotalDisplay/netWorthDisplay).
    public func displayMoneyBase(_ baseAmount: Double) -> String {
        if privacyMode { return FinchStore.moneyMask }
        let v = Money.convert(baseAmount, from: baseCurrency, to: displayCurrency, rates: rateMap) ?? baseAmount
        return Money.format(v, currency: displayCurrency)
    }
```

Change `displayMoney(_:forLedger:)` (does not delegate — needs its own gate):

```swift
    /// Format a ledger-base amount into that ledger's display currency (privacy-masked).
    public func displayMoney(_ baseAmount: Double, forLedger ledgerId: String) -> String {
        if privacyMode { return FinchStore.moneyMask }
        let base = baseCurrency(forLedger: ledgerId)
        let disp = displayCurrency(forLedger: ledgerId)
        let v = Money.convert(baseAmount, from: base, to: disp, rates: rateMap) ?? baseAmount
        return Money.format(v, currency: disp)
    }
```

Add `displayNative` next to them (the mask-aware replacement for direct `Money.format` in views — Task 2 consumes it):

```swift
    /// Format an amount already denominated in its own currency — no conversion,
    /// just format-or-mask. The privacy-aware replacement for calling
    /// Money.format directly in a view (web's `native` formatter).
    public func displayNative(_ amount: Double, currency: String) -> String {
        privacyMode ? FinchStore.moneyMask : Money.format(amount, currency: currency)
    }
```

- [ ] **Step 5: Run the tests to confirm they pass**

```bash
cd ios && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/PrivacyModeTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (4/4).

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/FinchStore.swift \
        ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift \
        ios/FinchApp/Tests/FinchAppTests/PrivacyModeTests.swift
git commit -m "feat(ios): FinchStore.privacyMode — masked display formatters (web #416 port)"
```

---

### Task 2: Toggles (eye button · palette · macOS menu) + direct-site swaps

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift` (add `PrivacyToggleButton` next to `LedgerBarButton`)
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`, `BudgetsTab.swift`, `ScheduledTab.swift`, `InsightsTab.swift`, `SettingsTab.swift` (toolbar item)
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/CommandPalette.swift` (palette entry)
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/FinchCommands.swift` (⌘⇧H menu item)
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift:99`, `ios/FinchApp/Sources/FinchApp/WriteScreens/SplitEditorView.swift:74-75` (route through `displayNative`)

**Interfaces:**
- Consumes (Task 1): `FinchStore.privacyMode`, `FinchStore.shared`, `displayNative(_:currency:)`.
- Produces: `struct PrivacyToggleButton: View`.

- [ ] **Step 1: Add `PrivacyToggleButton` to `AdaptiveShell.swift`**

Insert directly after the `LedgerBarButton` struct:

```swift
/// The privacy-mode eye toggle shown on every primary tab — one tap masks every
/// rendered amount as "••••" (web parity: #416). Cross-platform (not compact-gated:
/// useful on iPad/Mac toolbars too); state lives on FinchStore.privacyMode.
struct PrivacyToggleButton: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        Button { store.privacyMode.toggle() } label: {
            Image(systemName: store.privacyMode ? "eye.slash" : "eye")
        }
        .accessibilityLabel("Privacy mode")
    }
}
```

- [ ] **Step 2: Add the toolbar item to the 5 primary tabs**

In each tab's `.toolbar { … }` block, add as the **first** item (so the eye sits left of the `+`/overflow cluster):

```swift
                ToolbarItem(placement: .primaryAction) { PrivacyToggleButton() }
```

Exact spots:
- `AccountsTab.swift` — in the `.toolbar` block that holds the add/overflow items (before the `#if os(iOS)` editMode branch's ToolbarItem).
- `BudgetsTab.swift` — before the `ToolbarItem(placement: .primaryAction)` add button (~line 42).
- `ScheduledTab.swift` — before its add-button ToolbarItem.
- `InsightsTab.swift` — inside the existing `.toolbar { … }` (alongside the `#if os(iOS)` LedgerBarButton item, but **outside** the `#if` — the eye is cross-platform).
- `SettingsTab.swift` — inside the existing `.toolbar { … }` (alongside the `#if os(iOS)` LedgerBarButton item, outside the `#if`).

- [ ] **Step 3: Palette entry in `CommandPalette.swift`**

In `paletteCommands()`, after the "New Transaction" append:

```swift
    cmds.append(PaletteCommand(title: "Toggle Privacy Mode", systemImage: "eye") { _ in
        FinchStore.shared.privacyMode.toggle()
    })
```

- [ ] **Step 4: macOS menu item in `FinchCommands.swift`**

Extend the existing `CommandGroup(after: .toolbar)` block (which holds "Command Palette…") with a second button (static title — noting the spec allowed either):

```swift
            Button("Hide Amounts") { FinchStore.shared.privacyMode.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
```

- [ ] **Step 5: Route the direct sites through `displayNative`**

`AccountDetailView.swift:99` — change:
```swift
        let bal = Money.format(a.lastReconciledBalance ?? 0, currency: a.currency ?? store.baseCurrency)
```
to:
```swift
        let bal = store.displayNative(a.lastReconciledBalance ?? 0, currency: a.currency ?? store.baseCurrency)
```

`SplitEditorView.swift:74-75` — change:
```swift
                    LabeledContent("Transaction total", value: Money.format(total, currency: displayCurrency))
                    LabeledContent("Allocated", value: Money.format(allocated, currency: displayCurrency))
```
to:
```swift
                    LabeledContent("Transaction total", value: store.displayNative(total, currency: displayCurrency))
                    LabeledContent("Allocated", value: store.displayNative(allocated, currency: displayCurrency))
```
Leave line 126's validation error (`Money.format` in the "Splits must add up to" message) **unchanged** — actionable mid-edit feedback stays real per the spec.

- [ ] **Step 6: Build both platforms + full FinchAppTests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -only-testing:FinchAppTests 2>&1 | grep -iE "Executed .* tests|TEST SUCCEEDED|TEST FAILED|error:"
```
Expected: both `** BUILD SUCCEEDED **`; `** TEST SUCCEEDED **` (existing suite + the 4 new tests).

- [ ] **Step 7: Simulator visual check**

Install + launch (per the `ios-build-launch` skill). Verify:
- Tap the eye on Accounts → summary card, group subtotals, every row show `••••`; icon flips to `eye.slash`.
- Budgets / Scheduled / Insights (savings-rate label, net-worth card, recent expenses) / the pushed Ledger list all masked; budget progress bars and chart shapes still render.
- Account detail: balance header + reconciled-balance badge masked; split editor totals masked.
- Toggle off → figures restore instantly. Relaunch the app → state persisted.

- [ ] **Step 8: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift \
        ios/FinchApp/Sources/FinchApp/Shell/CommandPalette.swift \
        ios/FinchApp/Sources/FinchApp/Shell/FinchCommands.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/SplitEditorView.swift
git commit -m "feat(ios): privacy-mode toggles (eye on all tabs, palette, ⌘⇧H) + native-format mask"
```

---

## Self-Review

**1. Spec coverage:**
- State (`finch.privacy` UserDefaults, `@Published`, didSet persist) → Task 1 Step 3. ✅
- Mask `"••••"` in the core formatters (delegation noted: `displayMoney(from:)`/`subtotalDisplay`/`netWorthDisplay` inherit from `displayMoneyBase`; `forLedger:` gated separately) → Task 1 Step 4. ✅
- `displayNative` mechanism + the 4 direct sites (2 masked files; validation error stays real) → Task 1 Step 4 + Task 2 Step 5. ✅
- Eye on 5 tabs (cross-platform, not `#if`-gated) → Task 2 Steps 1-2. ✅
- Palette entry (`run` is `@MainActor (DeepLinkRouter) -> Void` — verified signature; `FinchStore.shared` OK) → Task 2 Step 3. ✅
- macOS ⌘⇧H → Task 2 Step 4. ✅
- Non-goals (no FinchCore/widgets/Watch/exports/inputs) → no task touches them. ✅
- Tests (mask on/off, persistence round-trip) + both builds + sim check → Task 1 Steps 1-5, Task 2 Steps 6-7. ✅

**2. Placeholder scan:** none — all steps carry complete code and commands with expected output.

**3. Type consistency:** `privacyMode`/`privacyKey`/`moneyMask`/`displayNative(_:currency:)` defined in Task 1 match every Task 2 usage; `PrivacyToggleButton` uses `@EnvironmentObject FinchStore` (injected app-wide in `FinchApp.swift`); palette closure discards the router arg (`{ _ in … }`) matching `(DeepLinkRouter) -> Void`.
