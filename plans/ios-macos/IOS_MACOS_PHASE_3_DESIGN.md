# finch for iOS & macOS — Phase 3 Implementation Design

> _Web facts verified vs commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13. See `_WEB_DRIFT_CHECKLIST.md`._

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce a
> step-by-step implementation plan for Phase 3.
>
> Companion documents:
>
> - `plans/ios-macos/IOS_MACOS_PLAN.md` — direction brief
> - `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 full design
> - `plans/ios-macos/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/ios-macos/IOS_MACOS_PHASE_3_DESIGN.md` (this file)
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0, 1.5, and 2 are complete; the read + write surfaces
> are shipped on iPhone._

## See also

- `plans/ios-macos/IOS_MACOS_INDEX.md` §3 — the master iPhone tab list (4→5→6 tabs)
- `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (6 tabs + 7 write screens)
- `plans/ios-macos/IOS_MACOS_PHASE_4_DESIGN.md` — Phase 4 (power features; runs on the same adaptive shell)
- `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 (iCloud + pack engine; same shell)
- `plans/ios-macos/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch; same shell)
- `plans/ios-macos/IOS_MACOS_PLAN.md` §6 — the multi-platform strategy

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (The adaptive shell itself) |
| §3. iOS UI surfaces | §3 (macOS menu bar + keyboard shortcuts) + §4 (the ⌘K command palette) + §5 (iPad-specific layout tweaks) |
| §4. Cross-cutting concerns | §2 (The adaptive shell is the cross-cutting concern) |
| §5. Wire contracts | §6 (Distribution: Mac App Store + direct download) |
| §6. CI / test infrastructure | §7 (CI changes) |
| §7. Out of scope (firm) | §9 |
| §8. Spec self-review + open questions | §10 + §8 |

## §1. Goal & non-goals

**Goal** — Adapt the iPhone app to **iPad** and **macOS** via
SwiftUI's adaptive containers. The same code base serves all
three platforms; the chrome switches by size class (iPhone =
bottom tab bar; iPad = sidebar + tab bar; Mac = sidebar + tab
bar + menu bar + keyboard shortcuts + ⌘K). The 6 tabs
(Accounts, Activity, Budgets, Insights, Reports, Scheduled —
post-Phase-2; note: "Reports" is the 5th tab, "Settings" is
a section, not a tab) + the 7 write screens from Phase 2
all render on all three platforms. **Both Mac distribution
paths** (Mac App Store + notarised direct download) are set up.

**Phase 3 is mostly a layout-distribution exercise.** The
chokepoint + selectors + parity tests from Phases 1.0-2 don't
change. Phase 3 adds:

- **`NavigationSplitView`** replaces `NavigationStack` on iPad
  and Mac (the existing iPhone `NavigationStack` is wrapped in
  a size-class check; the iPad/Mac path uses `NavigationSplitView`
  with a sidebar)
- **macOS menu bar** with the standard `File > Import .finch...`,
  `File > Export .finch...`, `Edit > Undo` (the chokepoint
  doesn't have an undo yet, so this is a stub), `View >
  Show Sidebar`, etc.
- **macOS keyboard shortcuts**: ⌘1-5 to switch tabs, ⌘N for new
  transaction, ⌘F for search, ⌘K for command palette
- **`⌘K command palette`** — the macOS analogue of the web's
  `command-palette`; searches across tabs, actions, and
  transaction detail
- **Multi-window support on iPad** (one window per active ledger
  — see Open questions)
- **Distribution**: Xcode project set up to produce both a Mac
  App Store + notarised direct download target

**Non-goals (firm)**:

- **New features** — no new tabs, no new write surfaces, no new
  selectors. Phase 3 is purely a layout + distribution
  exercise. The 6 tabs + 7 write screens are unchanged.
- **Watch** — that's Phase 7.
- **Widgets / Live Activities** — Phase 7.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **Row-level sync** — Phase 8.
- **Universal binary for Intel** — macOS 26 dropped Intel
  support; macOS 26+ (Apple Silicon) is the only supported
  target per the plan's §4.7.
- **iOS-on-Mac (Catalyst)** — only as a fallback per the plan's
  §4.1; not used in Phase 3.

**Estimated scope**: ~600-800 lines SwiftUI (the adaptive shell
+ multi-window plumbing + ⌘K + menu bar + keyboard shortcuts)
+ ~400 lines project setup (Xcode distribution config +
entitlements + sandbox config) + ~200 lines Mac-specific
parity tests. **1-2 months of full-time work** for a small
team. **Smallest of the read-write phases** because the
chokepoint + selectors + write surfaces are unchanged.

## §2. The adaptive shell

The Phase 1.0 spec's §5 describes the iPhone shell as a
`TabView` with 4 tabs (Accounts, Activity, Budgets, Settings;
Phase 1.5 adds Insights as the 5th; Phase 2 adds Scheduled
as the 6th, Reports is the 5th by display order — see
§2.1's size-class matrix). Phase 3 wraps this in an
**adaptive shell** that
switches chrome by size class.

The pattern mirrors the web's PageShell dispatcher (per the
CLAUDE.md note about PageShell.tsx being a 21-line dispatcher
that renders once and switches chrome by CSS). The iOS shell
is similar: one root view, one set of `NavigationStack` /
`NavigationSplitView` containers, a CSS-equivalent (size class
+ horizontal size class) check that switches the chrome.

### 2.1 — Size class matrix

| Device / size class | Chrome | Detail view |
|---|---|---|
| iPhone (compact width) | Bottom tab bar (6 tabs) | `NavigationStack` (push) |
| iPhone (regular width — iPhone Pro Max landscape) | Bottom tab bar (6 tabs) | `NavigationStack` (push) |
| iPad (regular width, both orientations) | Sidebar (6 tabs as a `List` in the leading column) | `NavigationSplitView` (2-column: sidebar + detail) |
| iPad (compact width — Slide Over / Split View 1/3) | Bottom tab bar (6 tabs) | `NavigationStack` (push) |
| Mac (any size) | Sidebar (6 tabs) + menu bar | `NavigationSplitView` (2-column: sidebar + detail) |

The check is a single SwiftUI `ViewThatFits` or `GeometryReader`
+ `horizontalSizeClass` + `horizontalSizeClass != .compact`
detection. The chrome is a `Group` of two views (tab-bar
variant + split-view variant) and SwiftUI picks the right one.

### 2.2 — The `AdaptiveShell` view

```swift
// ios/FinchApp/Shell/AdaptiveShell.swift
struct AdaptiveShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var store = FinchStore.shared

    var body: some View {
        if sizeClass == .compact {
            // iPhone: bottom tab bar + NavigationStack per tab
            TabBarShell(store: store)
        } else {
            // iPad / Mac: sidebar + NavigationSplitView
            SplitViewShell(store: store)
        }
    }
}
```

`TabBarShell` is the existing Phase 1.0 + 1.5 + 2 iPhone shell
(moved to its own file in Phase 3 for clarity). `SplitViewShell`
is the new Phase 3 iPad/Mac shell. They share the same
`FinchStore` + the same tab content (the 6 tabs from Phase
1.0/1.5/2 + the 7 write screens from Phase 2).

### 2.3 — `SplitViewShell`

```swift
// ios/FinchApp/Shell/SplitViewShell.swift
struct SplitViewShell: View {
    @State private var store: FinchStore
    @State private var selectedTab: AppTab = .accounts
    @State private var selectedEntryId: String? = nil  // for Transaction Detail

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)  // or .prominentDetail
    }

    private var sidebar: some View {
        // `List(selection:)` provides the link automatically
        // for each row; wrapping in `NavigationLink(value:)`
        // is double-handling and creates a nested-link
        // presentation.
        List(AppTab.allCases, selection: $selectedTab) { tab in
            Label(tab.title, systemImage: tab.icon)
        }
        .listStyle(.sidebar)
    }

    private var detail: some View {
        // Render the selected tab's content. If the user drilled
        // into a transaction detail, render that instead.
        if let entryId = selectedEntryId {
            TransactionDetailView(entryId: entryId)
        } else {
            tabContent(for: selectedTab)
        }
    }
}
```

`NavigationSplitView` provides the **standard iPad/Mac split
view**: a leading sidebar with the 6 tabs, a trailing detail
pane. Tapping a transaction row pushes `TransactionDetailView`
into the detail pane (the iPhone's `NavigationStack` push
becomes the iPad/Mac's split-view selection).

### 2.4 — Multi-window on iPad

`NavigationSplitView` is automatically multi-window-compatible
on iPadOS 26+. The `WindowGroup` in the iPhone app becomes a
`WindowGroup(for: AppTab.self)` (iPadOS's "selectable
scenes" pattern). The user can:

- Open the Accounts tab in one window
- Open the Activity tab in another window
- Each window is independent; the `FinchStore` is shared (the
  underlying DB is shared; the in-memory cache is per-window)

**Active-ledger-window-per-window**: the iPad user can have
one window per ledger (e.g., a "Personal" window and a
"Business" window side by side). The active-ledger switcher
in the Settings tab is now per-window. The `FinchStore.activeLedgerId`
is a `@State` per-window, not a singleton. Phase 2's
`FinchStore` is refactored to be window-scoped (or stays
singleton with a per-window `activeLedgerId` view; see Open
questions).

**iPad "drag to split view"**: the user drags an app icon from
the Dock to the side of the screen; iPadOS creates a new
window. The new window starts on the Accounts tab with the
active ledger. The user can then switch ledgers per-window.

## §3. The macOS menu bar + keyboard shortcuts

The macOS app's menu bar is the standard macOS chrome. SwiftUI
on macOS auto-derives most menu items from `Commands { ... }`
blocks in the `App` scene.

### 3.1 — Menu structure

```
finch
├── About finch
├── Settings...           ⌘,
├── ─────────
├── Hide finch            ⌘H
├── Hide Others           ⌘⌥H
├── Show All              (none)
├── ─────────
├── Quit finch            ⌘Q

File
├── New Transaction...    ⌘N    (opens Add Transaction form)
├── Open .finch...        ⌘O    (system file picker; imports a pack)
├── ─────────
├── Export .finch...      ⌘E    (share sheet; exports a pack)
├── ─────────
├── Close Window          ⌘W

Edit
├── Undo                  ⌘Z    (stub; chokepoint doesn't have undo yet)
├── Redo                  ⌘⇧Z  (stub)
├── ─────────
├── Cut                   ⌘X
├── Copy                  ⌘C
├── Paste                 ⌘V
├── ─────────
├── Find                  ⌘F    (Activity tab search)
├── Command Palette...    ⌘K    (universal search; see §4)

View
├── Accounts              ⌘1
├── Activity              ⌘2
├── Budgets               ⌘3
├── Insights              ⌘4
├── Scheduled             ⌘5
├── Settings              ⌘6
├── ─────────
├── Show Sidebar          ⌘⌥S
├── ─────────
├── Enter Full Screen     ⌘⌃F

Window
├── Minimize              ⌘M
├── Zoom
├── ─────────
├── Bring All to Front

Help
├── finch Help            (opens docs site in browser)
```

### 3.2 — Implementation

```swift
// ios/FinchApp/Shell/Commands.swift
@main
struct FinchApp: App {
    var body: some Scene {
        WindowGroup {
            AdaptiveShell()
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Transaction...") {
                    // Open Add Transaction form
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Open .finch...") { /* import */ }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Export .finch...") { /* export */ }
                    .keyboardShortcut("e", modifiers: .command)
            }
            // Edit menu
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { /* stub */ }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(true)  // chokepoint doesn't have undo
                Button("Redo") { /* stub */ }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(true)
            }
            // View menu
            CommandMenu("View") {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button(tab.title) {
                        // Switch to the tab
                    }
                    .keyboardShortcut(tab.shortcut, modifiers: .command)
                }
                Divider()
                Button("Show Sidebar") {
                    // Toggle the sidebar
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
    }
}
```

The `CommandGroup` API lets us add to / replace the standard
menus. The `keyboardShortcut` modifier binds a key combo.
SwiftUI on macOS auto-routes the shortcut to the menu item;
the user sees the shortcut next to the menu label.

## §4. The ⌘K command palette

`⌘K` is the macOS standard for "universal search" (every
modern Mac app has it: Spotlight, Alfred, Raycast, Linear,
Notion, etc.). The iOS app's ⌘K opens a modal sheet that
searches across:

- **Tabs**: "Accounts", "Activity", "Budgets", "Insights",
  "Scheduled", "Settings" — selecting one switches the active
  tab
- **Actions**: "New Transaction", "Import .finch", "Export
  .finch", "Switch Ledger", "Toggle Biometric Lock" — selecting
  one runs the action
- **Transactions**: "starbucks" — selecting one navigates to
  the Transaction Detail screen
- **Merchants**: "Starbucks" — selecting one filters the
  Activity tab to that merchant
- **Accounts**: "Chase Checking" — selecting one navigates to
  the account detail

The search is **client-side** (the in-memory `Tx[]` cache +
the `AccountRow[]` + `Counterparty[]` arrays). For the
**transactions** category, the search uses the FTS5 index
(Phase 1.0's `listTransactions(exec, { query })` query path).

### 4.1 — Implementation

```swift
// ios/FinchApp/Shell/CommandPalette.swift
struct CommandPalette: View {
    @State private var query: String = ""
    @State private var results: [CommandPaletteItem] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search commands, transactions, accounts...", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
            List(results) { item in
                Button(action: { runItem(item); dismiss() }) {
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.icon)
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
        .onChange(of: query) { _, newQuery in
            results = CommandPaletteEngine.search(query: newQuery, store: FinchStore.shared)
        }
    }
}

enum CommandPaletteEngine {
    static func search(query: String, store: FinchStore) -> [CommandPaletteItem] {
        guard !query.isEmpty else { return [] }
        var items: [CommandPaletteItem] = []
        // 1. Tab matches
        items += AppTab.allCases
            .filter { $0.title.lowercased().contains(query.lowercased()) }
            .map { .tab($0) }
        // 2. Action matches
        items += allActions
            .filter { $0.title.lowercased().contains(query.lowercased()) }
        // 3. Transaction matches (FTS5)
        items += try? store.searchTransactions(query: query)
            .prefix(10)
            .map { .transaction($0) }
        // 4. Merchant matches
        items += store.merchants
            .filter { $0.name.lowercased().contains(query.lowercased()) }
            .map { .merchant($0) }
        // 5. Account matches
        items += store.accounts
            .filter { $0.name.lowercased().contains(query.lowercased()) }
            .map { .account($0) }
        return items
    }
}
```

The ⌘K is bound in the menu bar (`Edit > Command Palette...
⌘K`) and also via a global `.keyboardShortcut` on the palette
view itself. The user invokes it from any tab; the result of
the selection may switch the active tab, navigate to a
detail, or run an action.

## §5. iPad-specific layout tweaks

The iPad layout is "sidebar + detail" via `NavigationSplitView`,
but the user can collapse the sidebar (the standard iPad
back-button or the `Show Sidebar ⌘⌥S` menu item). The
content adapts:

### 5.1 — Tab-specific iPad layouts

Some tabs benefit from a different layout on iPad:

- **Accounts tab**: the iPhone's grouped list becomes an iPad
  2-column layout (account group in the left column, accounts
  in the right column, mirroring the iPad Mail app's
  mailbox-list-message-list-detail pattern)
- **Insights tab**: the iPhone's vertical card stack becomes
  an iPad 2x3 grid of cards (net worth, cashflow, forecast,
  top movers, holdings, weekly digest)
- **Activity tab**: the iPhone's list + filter bar becomes an
  iPad 3-column layout (filters in the left column, transaction
  list in the middle, transaction detail in the right column —
  the standard iPad Mail pattern)
- **Budgets / Scheduled / Settings**: the iPhone's vertical
  list becomes an iPad single-column list with more padding
  (no special layout needed)

These are **iPad-only** tweaks. The iPhone path is unchanged.

### 5.2 — Pointer + keyboard interactions

The iPad (with a Magic Keyboard or trackpad) and Mac both
support **pointer interactions**:

- **Hover** on a transaction row: the row highlights, a
  "View" button appears
- **Click** on a transaction row: navigates to the detail
- **Right-click** on a transaction row: context menu
  (View, Edit, Mark Cleared, Mark Reviewed, Delete)
- **Swipe** on a transaction row (iPad only): the standard
  iOS swipe actions (Edit, Delete)
- **Pinch** on the Insights chart: zoom in/out (Phase 1.5's
  Swift Charts already support this on Mac)
- **Scroll** with a trackpad: smooth scrolling (Phase 1.0
  already supports this via `.scrollContentBackground`)

The web's keyboard shortcuts (j/k for next/prev transaction,
e for edit, etc.) are ported to Mac as ⌘↓/⌘↑ / ⌘E. The
iPad-with-Magic-Keyboard gets the same shortcuts; the iPad-
without-keyboard uses the touch interactions.

## §6. Distribution: Mac App Store + direct download

The Xcode project ships with **two distribution targets**:

1. **Mac App Store** — the default `archive` action with
   App Store signing. The `FINCH_APP_STORE` build setting
   enables the App Store sandbox + entitlements.
2. **Notarised direct download** — a `notarize` script that
   signs with a Developer ID, runs `xcrun altool --notarize-app`,
   staples the ticket, and packages a `.dmg` for download.

Both targets share the same codebase. The only differences are
in the entitlements (App Store is more restrictive on file
system access; the iCloud container works in both) and the
sandbox config (the direct download can use a less-restrictive
sandbox since the user trusts the developer).

### 6.1 — Entitlements

```xml
<!-- ios/FinchApp/FinchApp.entitlements (Mac App Store) -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.juchengquan.finch</string>
</array>
<key>com.apple.security.icloud-services</key>
<array>
    <string>CloudDocuments</string>
</array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.juchengquan.finch</string>
</array>
```

```xml
<!-- ios/FinchApp/FinchApp-Direct.entitlements (notarised direct) -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.juchengquan.finch</string>
</array>
<key>com.apple.security.cs.allow-jit</key>
<true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

The App Store version omits the `cs.*` keys (which would be
rejected by App Review). Both versions have the iCloud
container entitlement; the iCloud Drive `Documents/finch/`
folder is visible in Finder in both versions.

### 6.2 — Build pipeline

The `ios/scripts/build-mac-app-store.sh` and
`ios/scripts/build-mac-direct.sh` scripts automate the two
distribution paths:

```bash
# Mac App Store
xcodebuild -scheme FinchApp -configuration Release -archivePath build/finch.xcarchive archive
xcodebuild -exportArchive -archivePath build/finch.xcarchive -exportPath build/AppStore -exportOptionsPlist ios/AppStoreExportOptions.plist

# Notarised direct download
xcodebuild -scheme FinchApp -configuration Release -archivePath build/finch.xcarchive archive
xcodebuild -exportArchive -archivePath build/finch.xcarchive -exportPath build/Direct -exportOptionsPlist ios/DirectExportOptions.plist
xcrun altool --notarize-app --primary-bundle-id com.juchengquan.finch --username $APPLE_ID --password $APP_SPECIFIC_PASSWORD --file build/Direct/finch.pkg
xcrun stapler staple build/Direct/finch.dmg
```

CI runs both scripts on every release tag; the App Store
upload goes to App Store Connect, the direct download goes
to a download server.

## §7. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- An **iPad Simulator** destination: `xcodebuild test -scheme
  FinchApp -destination 'platform=iOS Simulator,name=iPad (11-inch)'`
- A **macOS** destination: `xcodebuild test -scheme FinchApp
  -destination 'platform=macOS'`
- A **UI snapshot test** for the iPad split-view shell
- A **UI snapshot test** for the Mac sidebar shell
- A **⌘K command palette** snapshot test (query, results,
  selection)
- The **distribution build pipeline** runs on release tags
  (the App Store + direct download archive + notarisation)

No structural change to the CI workflow; the existing
macos job from Phase 1.0 just gets more destinations.

## §8. Open questions

The plan's §14.1 still-open questions mostly land in later
phases. For Phase 3 specifically:

**Not blocking Phase 3 (decide later)**:

- **Multi-window on iPad**: one window per active ledger, or
  one window per tab? The proposal (one window per tab, with
  the active-ledger switcher per-window) is the simplest;
  Phase 4 may revise if the user research says otherwise.
- **⌘K result ranking**: when a query matches both a tab and
  a transaction, which ranks first? The proposal (tabs
  first, then actions, then transactions) is the simplest;
  Phase 1.5's search ranking may inform.
- **Mac App Store review**: the App Store's sandboxing rules
  are strict about file system access. The .finch import
  flow (system file picker) is allowed; the iCloud folder
  read is allowed. Any other file system access (e.g., the
  attachments `~/Library/Application Support/finch/`)
  requires an entitlement. The proposal has the right
  entitlements; review may surface a missing one.
- **Direct download update mechanism**: the notarised
  direct download doesn't auto-update. Options: (a)
  Sparkle framework; (b) a custom "check for updates" menu
  item; (c) skip auto-update (the user manually downloads a
  new version). The proposal is (c) for Phase 3 (skip); a
  later phase may add Sparkle.

**Specifically for the adaptive shell**:

- **`ViewThatFits` vs `GeometryReader` + size class**: SwiftUI
  on iOS 26+ supports `ViewThatFits` for adaptive layouts
  more cleanly than the `GeometryReader` + size-class
  approach. The proposal uses `horizontalSizeClass`; the
  implementation may use `ViewThatFits` if it's cleaner.
- **Sidebar vs bottom tab bar on iPhone Pro Max landscape**:
  the iPhone Pro Max in landscape is "regular width" per
  SwiftUI, which would put it in the split-view branch. The
  proposal overrides this (always use the tab bar on
  iPhone, regardless of size class) because the bottom tab
  bar is the iPhone idiom. The implementation may need a
  `UIDevice.current.userInterfaceIdiom` check in addition to
  the size class.

**Specifically for the menu bar**:

- **`Edit > Undo` is a stub**: the chokepoint doesn't have an
  undo yet. The proposal disables the menu item. A future
  phase may add undo (a Phase 2 chokepoint extension, not
  Phase 3).
- **`Help > finch Help` opens a browser**: the proposal opens
  the project docs site. If the docs site doesn't exist
  yet, the menu item is removed (or opens a placeholder).

**Not blocking Phase 3 because they're Phase 4+ by design**:

- **Power features** (reconcile, rules engine, transfers
  CRUD, etc.) — Phase 4. The action menu items are
  stubbed; the Phase 4 implementation wires them.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Widgets / Watch / Live Activities** — Phase 7.
- **Row-level sync** — Phase 8.

## §9. Out of scope (firm)

These are explicitly NOT in Phase 3:

- **New features** (no new tabs, no new write surfaces, no
  new selectors, no new actions)
- **Watch** — Phase 7
- **Widgets / Live Activities** — Phase 7
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5
- **Row-level sync** — Phase 8
- **iOS-on-Mac (Catalyst)** — only as a fallback per the
  plan's §4.1; not used in Phase 3
- **Universal binary for Intel** — macOS 26 dropped Intel
  support; macOS 26+ (Apple Silicon) only
- **In-app theme override** — Phase 3 follows the system
  light/dark setting
- **Auto-update via Sparkle** — the direct download is
  manually-updated for Phase 3; Sparkle is a follow-up
- **Undo for the chokepoint** — the menu item is stubbed;
  undo is a Phase 2 chokepoint extension, not Phase 3
- **Android** — not in the plan
- **Web parity features** (the iOS app gains no web-parity
  features in Phase 3; it's a layout exercise only)

## §10. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The menu structure is enumerated in full.
- **Internal consistency**: §2's adaptive shell (size class
  matrix) matches the plan's §3 SwiftUI multiplatform
  direction. §3's menu structure mirrors standard macOS app
  conventions. §6's entitlements are the canonical
  iCloud-container + sandbox shape.
- **Scope**: focused on Phase 3. Phases 1.0, 1.5, 2 are
  referenced as completed. Phase 4+ are explicitly out of
  scope (§9). The estimated scope (1-2 months) reflects the
  fact that this is a layout exercise; the chokepoint +
  selectors + write surfaces are unchanged.
- **Ambiguity**: §2's size class matrix is a concrete
  table. §3's menu structure is a concrete tree. §4's ⌘K
  command palette has a concrete code sketch. §6's
  entitlements are concrete XML. §8 enumerates the
  remaining open questions with proposed answers.
