import SwiftUI
import FinchCore

/// Phase 3 — the ⌘K command palette: a searchable list of navigation + actions,
/// the desktop analogue of the web's ⌘K. Filters by title; running an item
/// drives the shared router. Pure list of `PaletteCommand`s is computed from the
/// tabs + a couple of global actions.
struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let run: @MainActor (DeepLinkRouter) -> Void
}

/// The command catalogue (pure, given the tab list).
func paletteCommands() -> [PaletteCommand] {
    var cmds: [PaletteCommand] = AppTab.allCases.map { tab in
        PaletteCommand(title: "Go to \(tab.title)", systemImage: tab.icon) { $0.selectedTab = tab }
    }
    cmds.append(PaletteCommand(title: "New Transaction", systemImage: "plus.circle") { $0.showAddTransaction = true })
    return cmds
}

/// Case-insensitive substring filter (pure, testable).
func filterPalette(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return commands }
    return commands.filter { $0.title.lowercased().contains(q) }
}

struct CommandPalette: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [PaletteCommand] { filterPalette(paletteCommands(), query: query) }

    var body: some View {
        NavigationStack {
            List(results) { cmd in
                Button {
                    cmd.run(router)
                    dismiss()
                } label: {
                    Label(cmd.title, systemImage: cmd.systemImage)
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Type a command…")
            .navigationTitle("Commands")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
