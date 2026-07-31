# UIKit Navigation Host — Phase 1 (Infra + Budgets Pilot) Implementation Plan

> # ⚠️ SUPERSEDED — 2026-07-31. Historical record only.
>
> **This approach was abandoned. It does not fix the bug.** `UIKitNavStack` — hosting
> SwiftUI screens inside a `UINavigationController` — was device-tested and **still
> showed the resume shadow**. The shadow tracks navigation *depth* and the presence of
> a hosted SwiftUI scroll view, not which framework owns the navigation controller, so
> wrapping the same SwiftUI screens in UIKit chrome changes nothing.
>
> Neither `UIKitNavStack` nor `UIKitNavLink` exists in the codebase — grep returns
> nothing. What shipped instead is a full screen conversion: see
> **`uikit-migration-plan.md`**, Phases 0–2.
>
> **Its phase numbering conflicts with the live plan and will mislead you.** Here
> Phase 2 = Settings and Phase 3 = Accounts. In `uikit-migration-plan.md` — the one to
> follow — Phase 2 = convert the pushed destinations and Phase 3 = iPad.
>
> Kept because the design constraints it records (toolbar/searchable bridging, the
> lock-overlay security gate, the ledger-push seam) were re-encountered and remain
> accurate.

> **Execution model — inline, device-gated (not subagent dispatch).** The acceptance
> gate is on a physical device (the iOS 26 resume shadow does not reproduce faithfully
> on the simulator), and the agent cannot codesign — so tasks run inline in this
> session: the agent writes code, builds for the sim, and drives the device
> install/verify loop, while the **maintainer runs the one signed device build** at
> Task 3. This is why the plan is not handed to `subagent-driven-development` (its
> subagents can't run the device loop). Steps use checkbox (`- [ ]`) syntax; each task
> ends at an independently committable + verifiable point.

**Goal:** Build the reusable iOS-only `UIKitNavStack` navigation component and prove it on the **Budgets** tab — a compact pushed budget-detail list that no longer shows the iOS 26 resume glass shadow, with slide-from-right push and full `.soft` transparency.

**Architecture:** A `UIViewControllerRepresentable` wrapping `UINavigationController` hosts each compact tab's content; pushes go through a UIKit push of an env-decorated `UIHostingController`. Pushed views keep their `.toolbar`/`.searchable`/`.navigationTitle`/`\.dismiss` via UIHostingController bridging (screenshot-proven). iPad/Mac's three-column path is untouched.

**Tech Stack:** SwiftUI + UIKit interop (`UIViewControllerRepresentable`, `UIHostingController`, `UINavigationController`), iOS 26. Spec: `ios/docs/uikit-navigation-host-design.md`.

## Global Constraints

- **Compact iOS only.** All new types are `#if os(iOS)`. The iPad/Mac (`selection != nil`) branch and the macOS branch keep `NavigationStack` byte-for-byte.
- **No changes to pushed views** (`BudgetDetailView`, etc.) — they migrate untouched.
- **Environment decorator injects exactly three objects** — `FinchStore`, `DeepLinkRouter`, `BiometricGate` (the only `@EnvironmentObject`s in the app) — plus `\.navPush` / `\.navPopToRoot`.
- **Device is the acceptance gate:** scroll a pushed page → background → resume → **no shadow**; and toolbar/search/title/back/multi-level-push/dismiss all work. Sim contrast metric (<~15) is a cheap pre-check only.
- Builds that must stay green: FinchApp (iOS), **FinchMac** (macOS), FinchWatch, `ci-local` (356 + 320 tests, i18n guard).
- Work in a clean worktree off `feat/frontend`; revert the throwaway prototype/device patches in `/private/tmp/finch-tabblock` first (do not carry them in).

---

### Task 1: Build the `UIKitNavStack` infra

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Shell/UIKitNavStack.swift`

**Interfaces produced (later tabs consume these):**
- `UIKitNavStack<Root: View>(prefersLargeTitles:Bool = true, @ViewBuilder root: () -> Root)`
- `UIKitNavLink<Label, Destination>(@ViewBuilder destination:, @ViewBuilder label:)`
- `EnvironmentValues.navPush: (AnyView) -> Void`, `.navPopToRoot: () -> Void`
- `View.ledgerPushUIKit()` — the UIKit-path replacement for `.ledgerPush()`

- [ ] **Step 1: Write the file** (concrete code — this is the whole component):

```swift
#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Push facade (Environment)

private struct NavPushKey: EnvironmentKey { static let defaultValue: (AnyView) -> Void = { _ in } }
private struct NavPopToRootKey: EnvironmentKey { static let defaultValue: () -> Void = { } }
extension EnvironmentValues {
    /// Push an arbitrary view onto the enclosing `UIKitNavStack` (slide-from-right).
    var navPush: (AnyView) -> Void { get { self[NavPushKey.self] } set { self[NavPushKey.self] = newValue } }
    /// Pop back to the tab root.
    var navPopToRoot: () -> Void { get { self[NavPopToRootKey.self] } set { self[NavPopToRootKey.self] = newValue } }
}

extension View {
    /// Re-inject the app-wide environment onto a view about to be hosted in a
    /// pushed `UIHostingController`, which does NOT inherit SwiftUI environment.
    /// Injects the three app `@EnvironmentObject`s plus the push facade so deeper
    /// pushes work.
    func finchNavEnvironment(store: FinchStore, router: DeepLinkRouter, gate: BiometricGate,
                             push: @escaping (AnyView) -> Void, popToRoot: @escaping () -> Void) -> some View {
        self.environmentObject(store).environmentObject(router).environmentObject(gate)
            .environment(\.navPush, push).environment(\.navPopToRoot, popToRoot)
    }
}

// MARK: - Container

/// A UIKit `UINavigationController`-backed navigation container for a compact tab.
/// Unlike SwiftUI `NavigationStack`, it does NOT re-sample the pushed view's
/// scroll-edge glass on resume, so no iOS 26 shadow forms. `.toolbar` /
/// `.searchable` / `.navigationTitle` / `\.dismiss` bridge to the nav controller.
struct UIKitNavStack<Root: View>: UIViewControllerRepresentable {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var gate: BiometricGate
    private let root: Root
    private let prefersLargeTitles: Bool

    init(prefersLargeTitles: Bool = true, @ViewBuilder root: () -> Root) {
        self.root = root(); self.prefersLargeTitles = prefersLargeTitles
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UINavigationController {
        let c = context.coordinator
        c.store = store; c.router = router; c.gate = gate
        let rootVC = UIHostingController(rootView: root.finchNavEnvironment(
            store: store, router: router, gate: gate,
            push: { [weak c] in c?.push($0) }, popToRoot: { [weak c] in c?.popToRoot() }))
        let nav = UINavigationController(rootViewController: rootVC)
        nav.navigationBar.prefersLargeTitles = prefersLargeTitles
        c.nav = nav
        return nav
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {
        // Singletons with stable identity — refresh refs so late pushes stay valid.
        context.coordinator.store = store
        context.coordinator.router = router
        context.coordinator.gate = gate
    }

    final class Coordinator {
        weak var nav: UINavigationController?
        var store: FinchStore?; var router: DeepLinkRouter?; var gate: BiometricGate?
        func push(_ view: AnyView) {
            guard let store, let router, let gate else { return }
            let vc = UIHostingController(rootView: view.finchNavEnvironment(
                store: store, router: router, gate: gate,
                push: { [weak self] in self?.push($0) }, popToRoot: { [weak self] in self?.popToRoot() }))
            nav?.pushViewController(vc, animated: true)
        }
        func popToRoot() { nav?.popToRootViewController(animated: true) }
    }
}

// MARK: - Declarative link (drop-in for NavigationLink { Dest } label: { Row })

struct UIKitNavLink<Label: View, Destination: View>: View {
    @Environment(\.navPush) private var navPush
    private let destination: () -> Destination
    private let label: () -> Label
    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination; self.label = label
    }
    var body: some View {
        Button { navPush(AnyView(destination())) } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

// MARK: - Ledger push (UIKit-path replacement for `.ledgerPush()`)

private struct LedgerPushUIKit: ViewModifier {
    @EnvironmentObject private var router: DeepLinkRouter
    @Environment(\.navPush) private var navPush
    func body(content: Content) -> some View {
        content.onChange(of: router.showLedger) { _, show in
            if show { navPush(AnyView(LedgerListView())); router.showLedger = false }
        }
    }
}
extension View {
    /// Compact UIKitNavStack replacement for `.ledgerPush()`: the top-left Ledger
    /// control (`router.showLedger`) pushes the Ledger list via UIKit.
    func ledgerPushUIKit() -> some View { modifier(LedgerPushUIKit()) }
}
#endif
```

- [ ] **Step 2: Regenerate + build for sim.** `cd ios && xcodegen generate` (new file), then
  `xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID"`.
  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit.** `feat(ios): UIKitNavStack — UIKit navigation container to avoid iOS 26 resume glass shadow`.

---

### Task 2: Migrate the Budgets compact path to `UIKitNavStack`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift`

**Interfaces consumed:** `UIKitNavStack`, `\.navPush`, `ledgerPushUIKit()` from Task 1.

Rationale: compact Budgets already branches from iPad — compact rows `Button { path.append(id) }` + `.navigationDestination(for: String.self)`; iPad rows are `List(selection:)` tags. Only the compact branch moves to UIKit; `path` and `.navigationDestination` become the iPad-only branch's concern.

- [ ] **Step 1: Add the push env reader.** In `BudgetsTab`, after the `@EnvironmentObject`s add:

```swift
    #if os(iOS)
    @Environment(\.navPush) private var navPush
    #endif
```

- [ ] **Step 2: Extract the shared inner content.** Pull the current `NavigationStack(path: $path) { … }` body (everything from `listContent` through the `#if os(iOS) .environment(\.editMode …) #endif` chain) into a computed `@ViewBuilder private var budgetsInner: some View` — but **without** `.navigationDestination(for: String.self)` and **without** `.ledgerPush()` (those stay branch-specific, next step).

- [ ] **Step 3: Split the container.** Replace `var body` with:

```swift
    var body: some View {
        #if os(iOS)
        if selection == nil {
            UIKitNavStack { budgetsInner.ledgerPushUIKit() }
        } else {
            NavigationStack(path: $path) {
                budgetsInner
                    .navigationDestination(for: String.self) { BudgetDetailView(budgetId: $0) }
                    .ledgerPush()
            }
        }
        #else
        NavigationStack(path: $path) {
            budgetsInner
                .navigationDestination(for: String.self) { BudgetDetailView(budgetId: $0) }
                .ledgerPush()
        }
        #endif
    }
```

- [ ] **Step 4: Compact row uses `navPush`.** In `contentList`'s `else` (compact) branch, change:

```swift
Button { path.append(budget.id) } label: {
```
to:
```swift
Button { navPush(AnyView(BudgetDetailView(budgetId: budget.id))) } label: {
```

- [ ] **Step 5: Deep-link focus uses `navPush` in compact.** In `consumeFocus()`, change the compact branch:

```swift
if let selection { selection.wrappedValue = id }
else { path = [id] }
```
to:
```swift
if let selection { selection.wrappedValue = id }
#if os(iOS)
else { navPush(AnyView(BudgetDetailView(budgetId: id))) }
#else
else { path = [id] }
#endif
```

- [ ] **Step 6: Build for sim.** `BUILD SUCCEEDED`. Launch `-initialTab budgets`, tap a budget → confirm slide-from-right push into `BudgetDetailView`, back works, search + `+` + reorder ✕/✓ toolbar all render on the root, and the Ledger bar-button pushes the Ledger list.

- [ ] **Step 7: Sim contrast pre-check.** Scroll the pushed budget detail, background/resume, run the contrast metric (`$CLAUDE_JOB_DIR` venv + `energy2.py`). Expected < ~15 (root/UIKit-like), not ~47.

- [ ] **Step 8: Commit.** `feat(ios): route compact Budgets pushes through UIKitNavStack (no iOS 26 resume shadow)`.

---

### Task 3: Device acceptance + regression gates

**No code** unless a gate fails (then STOP and diagnose — likely the env decorator or root-toolbar bridging; fall back per the spec's edge-cases list).

- [ ] **Step 1: Device build.** Maintainer runs the signed build (worktree path) per `ios-device-sample-data`; agent installs over the existing app (no wipe) via `devicectl`.
- [ ] **Step 2: DEVICE acceptance (the gate).** Budgets → open a budget → scroll → background → resume → **confirm NO shadow.** Also confirm: title/back/search/toolbar render; back-swipe works; a 2-level push (budget detail → any deeper push) works; `\.dismiss` from the detail pops.
- [ ] **Step 3: iPad regression.** iPad sim: Budgets three-column still selects into the detail column (unchanged).
- [ ] **Step 4: Full build/test.** `ci-local` (FinchCore 356 + FinchApp 320 + i18n), FinchMac, FinchWatch all green.
- [ ] **Step 5: Decision point.** If the device gate passes → proceed to Phase 2 plan (Settings), then Accounts (removing the #628 modal), then the rest. If root-toolbar bridging or dismiss fails → adjust the infra (spec edge-cases) and re-verify before scaling.

---

## Follow-up phases (separate plans, after the pilot passes on device)

- **Phase 2 — Settings** (14 `NavigationLink` → `UIKitNavLink`).
- **Phase 3 — Accounts** (drill-ins → `navPush`; remove the #628 `fullScreenCover` modal, the `DrillTarget` enum, and the debug prototype harness).
- **Phase 4 — Scheduled, Ledger, Activity, PowerTools, deep links.**
- **Phase 5 — docs:** update `ios/docs/ios26-liquid-glass-artifacts.md`; resolve PR #628 (keep its tab-switch fix, drop its modal).

## Self-review notes

- Spec coverage: Task 1 = components + decorator + ledger-push; Task 2 = one migration exercising `UIKitNavStack` + `navPush` + `ledgerPushUIKit` + deep-link; Task 3 = the device gate + iPad/build regressions. `UIKitNavLink` is built in Task 1 but first *used* in Phase 2 (Settings) — intentional (Budgets pushes are state/row-driven, not declarative links).
- Risk: `\.dismiss`→pop and root-toolbar bridging are validated by Task 3 Step 2; fallbacks in the spec.
