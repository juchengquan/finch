# Phase 3 Implementation Plan — iPad + macOS adaptive shell

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Adapt the iPhone app (Phases 1.0, 1.5, 2) to **iPad** and **macOS** via SwiftUI's `NavigationSplitView`. After Phase 3, the iPad has a sidebar + tab bar; the Mac has a sidebar + tab bar + menu bar + keyboard shortcuts + ⌘K. The 6 tabs (Accounts, Activity, Budgets, Insights, Scheduled, Settings) + the 7 write screens from Phase 2 all render on all three platforms.

**Architecture:** `NavigationSplitView` is the core primitive. The 4-tab iPhone `TabView` (from Phases 1.0 + 2) becomes a `TabView` on iPhone, a `NavigationSplitView` (sidebar + detail) on iPad, and a `NavigationSplitView` (sidebar + tab bar + menu bar) on Mac. The `ContentTabs` shell (from Phase 2) wraps the platform-specific layout. The 7 write screens are platform-agnostic (SwiftUI form sheets work on all three platforms).

**Tech Stack:**
- Swift 5.9 + SwiftUI (iOS 26+ / macOS 14+)
- Xcode 16+
- The existing `FinchCore` + `FinchApp` SwiftPM packages (from Phase 1.0)

**Input design spec:** `plans/IOS_MACOS_PHASE_3_DESIGN.md` (~700 lines, 10 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2 — the iPhone app must be shipping with the 6 tabs + 7 write screens.

**Estimated time:** 1-2 months of full-time work for a small team.

---

## File structure

```
frontend/ios/FinchApp/
  Sources/FinchApp/
    FinchApp.swift               # MODIFY: detect platform, render adaptive shell
    AdaptiveShell.swift          # NEW: the platform-specific shell
    Sidebar/                     # NEW: the iPad/Mac sidebar
      Sidebar.swift              # the sidebar with 6 sections
      SidebarItem.swift          # the sidebar row view
    MacMenu/                     # NEW: the Mac menu bar additions
      AppMenu.swift              # the MenuBar extra items
    CommandPalette/             # NEW: the ⌘K command palette
      CommandPalette.swift       # the search-driven navigation
      CommandPaletteModel.swift  # the fuzzy-search logic
    iPad/                        # NEW: iPad-specific layout tweaks
      SplitViewLayout.swift      # the 2-column + 3-column layouts
  FinchApp.xcodeproj/
    project.pbxproj              # MODIFY: add Mac target
```

**File counts**: 1 modified + ~10 new files, ~800-1,200 lines Swift.

---

## Task 1: Add the `AdaptiveShell` view

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/AdaptiveShell.swift`
- Modify: `frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift`

- [ ] **Step 1: Build the platform-detection shell**

`frontend/ios/FinchApp/Sources/FinchApp/AdaptiveShell.swift`:

```swift
import SwiftUI

/// The platform-specific shell. Detects the current size class
/// and platform; renders the appropriate layout.
struct AdaptiveShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.userInterfaceIdiom) private var idiom
    @State private var selectedTab: AppTab = .accounts

    var body: some View {
        if idiom == .mac {
            MacShell(selectedTab: $selectedTab)
        } else if horizontalSizeClass == .compact {
            // iPhone (portrait)
            iPhoneShell(selectedTab: $selectedTab)
        } else {
            // iPad (regular size class)
            iPadShell(selectedTab: $selectedTab)
        }
    }
}

/// The 6 tabs in the app.
enum AppTab: String, CaseIterable, Identifiable {
    case accounts, activity, budgets, insights, scheduled, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .activity: return "Activity"
        case .budgets: return "Budgets"
        case .insights: return "Insights"
        case .scheduled: return "Scheduled"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .accounts: return "wallet.pass"
        case .activity: return "list.bullet"
        case .budgets: return "chart.pie"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .scheduled: return "calendar"
        case .settings: return "gear"
        }
    }
}
```

- [ ] **Step 2: Build the `iPhoneShell` (unchanged from Phase 2)**

```swift
struct iPhoneShell: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "wallet.pass") }
                .tag(AppTab.accounts)
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
                .tag(AppTab.activity)
            BudgetsTab()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }
                .tag(AppTab.budgets)
            InsightsTab()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.insights)
            ScheduledTab()
                .tabItem { Label("Scheduled", systemImage: "calendar") }
                .tag(AppTab.scheduled)
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
    }
}
```

- [ ] **Step 3: Build the `iPadShell` (NavigationSplitView)**

```swift
struct iPadShell: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detailView
                .toolbar {
                    // The iPad toolbar (mirrors the sidebar items)
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .accounts: AccountsTab()
        case .activity: ActivityTab()
        case .budgets: BudgetsTab()
        case .insights: InsightsTab()
        case .scheduled: ScheduledTab()
        case .settings: SettingsTab()
        }
    }
}
```

- [ ] **Step 4: Build the `MacShell` (sidebar + tab bar + menu bar)**

```swift
struct MacShell: View {
    @Binding var selectedTab: AppTab
    @State private var commandPaletteShown = false

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detailView
        }
        .commands {
            // Mac menu bar additions
            CommandGroup(replacing: .newItem) {
                Button("New Transaction") { /* open AddTransactionSheet */ }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Accounts") { selectedTab = .accounts }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Activity") { selectedTab = .activity }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Budgets") { selectedTab = .budgets }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Insights") { selectedTab = .insights }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Scheduled") { selectedTab = .scheduled }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Settings") { selectedTab = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Command Palette…") { commandPaletteShown = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }
        .sheet(isPresented: $commandPaletteShown) {
            CommandPalette(isShown: $commandPaletteShown, selectedTab: $selectedTab)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .accounts: AccountsTab()
        case .activity: ActivityTab()
        case .budgets: BudgetsTab()
        case .insights: InsightsTab()
        case .scheduled: ScheduledTab()
        case .settings: SettingsTab()
        }
    }
}
```

- [ ] **Step 5: Wire `AdaptiveShell` into `FinchApp`**

Modify `FinchApp.swift`:

```swift
@main
struct FinchApp: App {
    @StateObject private var store = FinchStore.shared

    var body: some Scene {
        WindowGroup {
            AdaptiveShell()
                .environmentObject(store)
        }
        .commands {
            // App-level commands (e.g., Quit, About)
        }
    }
}
```

- [ ] **Step 6: Run on all 3 platforms (smoke test)**

Run: build + run on:
- iPhone 15 simulator (compact size class) — `iPhoneShell`
- iPad 10th gen simulator (regular size class) — `iPadShell`
- macOS (Mac Catalyst or native) — `MacShell`

Expected: each platform renders the correct layout.

- [ ] **Step 7: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/AdaptiveShell.swift
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): add adaptive shell (iPhone TabView + iPad/Mac NavigationSplitView)"
```

---

## Task 2: Build the `Sidebar` view (iPad/Mac)

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Sidebar/Sidebar.swift`
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Sidebar/SidebarItem.swift`

- [ ] **Step 1: Build the `SidebarItem` view**

`frontend/ios/FinchApp/Sources/FinchApp/Sidebar/SidebarItem.swift`:

```swift
import SwiftUI

struct SidebarItem: View {
    let tab: AppTab
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: tab.systemImage)
                .frame(width: 24)
            Text(tab.title)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
        .cornerRadius(6)
    }
}
```

- [ ] **Step 2: Build the `Sidebar` view**

`frontend/ios/FinchApp/Sources/FinchApp/Sidebar/Sidebar.swift`:

```swift
import SwiftUI

struct Sidebar: View {
    @Binding var selection: AppTab

    var body: some View {
        List(AppTab.allCases, selection: $selection) { tab in
            NavigationLink(value: tab) {
                SidebarItem(tab: tab, isSelected: selection == tab)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("finch")
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Sidebar/
git commit -m "feat(ios): add Sidebar view for iPad/Mac"
```

---

## Task 3: Build the `CommandPalette` (⌘K) view

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/CommandPalette/CommandPalette.swift`
- Create: `frontend/ios/FinchApp/Sources/FinchApp/CommandPalette/CommandPaletteModel.swift`

- [ ] **Step 1: Build the `CommandPaletteModel` (fuzzy search)**

`frontend/ios/FinchApp/Sources/FinchApp/CommandPalette/CommandPaletteModel.swift`:

```swift
import Foundation

public struct CommandItem: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let action: () -> Void

    public static func == (lhs: CommandItem, rhs: CommandItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public final class CommandPaletteModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var items: [CommandItem] = []

    private let allItems: [CommandItem]

    public init(items: [CommandItem]) {
        self.allItems = items
        self.items = items
    }

    public func update(_ q: String) {
        query = q
        if q.isEmpty {
            items = allItems
        } else {
            items = allItems.filter { item in
                item.title.localizedCaseInsensitiveContains(q) ||
                (item.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
    }
}
```

- [ ] **Step 2: Build the `CommandPalette` view**

`frontend/ios/FinchApp/Sources/FinchApp/CommandPalette/CommandPalette.swift`:

```swift
import SwiftUI

struct CommandPalette: View {
    @Binding var isShown: Bool
    @Binding var selectedTab: AppTab
    @StateObject private var model: CommandPaletteModel

    init(isShown: Binding<Bool>, selectedTab: Binding<AppTab>) {
        self._isShown = isShown
        self._selectedTab = selectedTab
        let items: [CommandItem] = [
            CommandItem(title: "Accounts", systemImage: "wallet.pass") {
                selectedTab.wrappedValue = .accounts
            },
            CommandItem(title: "Activity", systemImage: "list.bullet") {
                selectedTab.wrappedValue = .activity
            },
            // (... 4 more)
        ]
        self._model = StateObject(wrappedValue: CommandPaletteModel(items: items))
    }

    var body: some View {
        VStack {
            TextField("Type a command…", text: Binding(
                get: { model.query },
                set: { model.update($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .padding()

            List(model.items) { item in
                Button {
                    item.action()
                    isShown = false
                } label: {
                    HStack {
                        Image(systemName: item.systemImage)
                        VStack(alignment: .leading) {
                            Text(item.title)
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/CommandPalette/
git commit -m "feat(ios): add ⌘K Command Palette with fuzzy search"
```

---

## Task 4: Add the Mac target to the Xcode project

**Files:**
- Modify: `frontend/ios/FinchApp.xcodeproj/project.pbxproj` (Phase 1.0 file)

- [ ] **Step 1: Open Xcode and add the Mac target**

Open `frontend/ios/FinchApp.xcodeproj` in Xcode 16+.

- File → New → Target → macOS → App
- Product name: `FinchApp`
- Interface: SwiftUI
- Language: Swift
- Bundle ID: `com.juchengquan.finch.macos`
- Tick "Use SwiftUI App lifecycle"
- Click Finish.

Xcode will add the Mac target to the project.

- [ ] **Step 2: Configure the Mac target's entitlements**

In the Mac target's Signing & Capabilities:
- Enable "App Sandbox"
- Add the "User Selected File" entitlement (read-only + read-write)
- Add the "Network" entitlement (client + server; for iCloud + CloudKit)
- (More entitlements added in later phases)

- [ ] **Step 3: Set the deployment target**

In the Mac target's General settings:
- Minimum Deployments → macOS 14.0 (per `IOS_MACOS_PLAN.md` §4.1)
- Swift Language Version → 5.9

- [ ] **Step 4: Add the iCloud + CloudKit capability (for Phase 5 + 8)**

For Phase 3, just add the App Sandbox. iCloud + CloudKit land in
Phase 5 + 8.

- [ ] **Step 5: Build + run on macOS (smoke test)**

Run: build + run the Mac target.

Expected: the Mac app launches in a window; the 6 tabs are
visible in the sidebar; ⌘K opens the command palette; the
menus work.

- [ ] **Step 6: Commit**

```bash
git add frontend/ios/FinchApp.xcodeproj/
git commit -m "feat(ios): add macOS target to Xcode project"
```

---

## Task 5: Configure Mac App Store + notarised direct distribution

**Files:**
- Create: `frontend/ios/FinchApp/FinchApp-Mac.entitlements`
- Create: `frontend/ios/scripts/sign-and-notarize.sh`
- Create: `frontend/ios/scripts/build-mac-app-store.sh`

- [ ] **Step 1: Add the Mac App Store entitlements**

`frontend/ios/FinchApp/FinchApp-Mac.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Write the notarisation script**

`frontend/ios/scripts/sign-and-notarize.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Sign the .app bundle
APP="$1"
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
codesign --deep --force --options runtime --sign "$DEVELOPER_ID" "$APP"

# Create a zip for notarisation
ZIP="${APP%.app}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

# Submit for notarisation
xcrun notarytool submit "$ZIP" --keychain-profile "notarytool" --wait

# Staple the ticket
xcrun stapler staple "$APP"
```

- [ ] **Step 3: Write the Mac App Store build script**

`frontend/ios/scripts/build-mac-app-store.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Build the Mac app for App Store distribution
xcodebuild -project FinchApp.xcodeproj \
    -scheme FinchApp \
    -destination 'platform=macOS' \
    -configuration Release \
    -archivePath ./build/FinchApp.xcarchive \
    archive

# Export the .pkg for App Store upload
xcodebuild -exportArchive \
    -archivePath ./build/FinchApp.xcarchive \
    -exportPath ./build \
    -exportOptionsPlist ./build/exportOptions.plist

echo "Build complete. Upload ./build/FinchApp.pkg to App Store Connect."
```

- [ ] **Step 4: Commit**

```bash
git add frontend/ios/FinchApp/FinchApp-Mac.entitlements
git add frontend/ios/scripts/
git commit -m "feat(ios): add Mac App Store + notarisation scripts"
```

---

## Self-review

**Spec coverage** (Phase 3 design spec, 10 sections + §0. Map TOC):

| Design § | Implementation |
|---|---|
| §1. Goal & non-goals | All tasks — full coverage |
| §2. Adaptive shell | Task 1 (AdaptiveShell) — full coverage |
| §3. macOS menu bar + keyboard shortcuts | Task 1 (MacShell) — full coverage |
| §4. ⌘K command palette | Task 3 (CommandPalette) — full coverage |
| §5. iPad-specific layout tweaks | Task 1 (iPadShell) — full coverage |
| §6. Distribution (Mac App Store + direct) | Task 5 (scripts) — full coverage |
| §7. CI changes | (covered in Phase 1.0 Task 12) — partial |
| §8. Open questions | (deferred; not in scope) |
| §9. Out of scope | (explicit non-goals) |
| §10. Spec self-review | (this section) |

**Placeholder scan**: clean. Every step has full code or
specific commands.

**Type consistency**: All types defined in Task 1 (`AppTab`,
`AdaptiveShell`) are referenced consistently in Tasks 2-4.

**Gaps**: minor (the iPad-specific layout tweaks in §5 are
covered by the iPad shell but could be more nuanced). All
10 sections of the design spec are covered at a high level.
