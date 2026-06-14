import SwiftUI

/// Phase 3 (Mac polish) — the menu-bar commands + keyboard shortcuts. On macOS
/// these populate the menu bar; on iPad (hardware keyboard) they're discoverable
/// via ⌘-hold. They drive the shared DeepLinkRouter. ⌘K opens the command
/// palette, ⌘N adds a transaction, ⌘1–6 switch tabs.
struct FinchCommands: Commands {
    @ObservedObject var router = DeepLinkRouter.shared

    var body: some Commands {
        // ⌘N — new transaction (replaces the default "New" item).
        CommandGroup(replacing: .newItem) {
            Button("New Transaction") { router.showAddTransaction = true }
                .keyboardShortcut("n", modifiers: .command)
        }
        // ⌘K — command palette (under a Find-adjacent group).
        CommandGroup(after: .toolbar) {
            Button("Command Palette…") { router.showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
        }
        // ⌘, — Settings (the standard Mac slot). finch keeps Settings as a tab,
        // so this focuses it rather than opening a separate Preferences window.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { router.selectedTab = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }
        // A "Go" menu: ⌘1–6 to switch tabs.
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { router.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
