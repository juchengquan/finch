import SwiftUI
import FinchCore

/// The Ledger tab (home, slot #1) — a lean ledger overview: active ledger +
/// switcher, net worth, display currency, and this-month income/expense, with a
/// "View all activity" link into the full feed (the feed itself also lives in the
/// Accounts summary). Top-right overflow menu manages ledgers.
struct LedgerTab: View {
    @State private var showingManage = false

    var body: some View {
        NavigationStack {
            List {
                LedgerHeaderSection()
                Section {
                    NavigationLink {
                        ActivityFeedView()
                    } label: {
                        Label("View all activity", systemImage: "list.bullet")
                    }
                }
            }
            .navigationTitle("Ledger")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }   // .topBarLeading is iOS-only; gear is compact-only anyway (macOS uses the sidebar)
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingManage = true } label: { Label("Manage ledgers", systemImage: "books.vertical") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .navigationDestination(isPresented: $showingManage) { LedgerManagementView() }
            .settingsPush()
        }
    }
}

/// Ledger-context summary at the top of the Ledger tab: active ledger name with
/// a switcher menu, net worth, display currency, and this-month income/expense.
/// (Manage-ledgers lives in the tab's top-right overflow menu.)
private struct LedgerHeaderSection: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingLedgerPicker = false
    private var activeName: String { store.ledgers.first { $0.id == store.activeLedgerId }?.name ?? "Ledger" }

    private var thisMonth: (inc: Double, exp: Double) {
        let p = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, String(store.today.prefix(7)), 1).first
        return (p?.inc ?? 0, p?.exp ?? 0)
    }

    var body: some View {
        Group {
            Section {
                HStack {
                    // Plain button + confirmationDialog instead of a Menu: the Menu's
                    // label mis-measured on a name swap and clipped the leading glyph
                    // ("Personal" → "ersonal"). A normal Text label doesn't.
                    Button { showingLedgerPicker = true } label: {
                        HStack(spacing: 4) {
                            Text(activeName).font(.title3.weight(.semibold))
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingLedgerPicker) {
                        ledgerPicker.presentationCompactAdaptation(.popover)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Net worth").font(.caption2).foregroundStyle(.secondary)
                        Text(store.netWorthDisplay).font(.headline)
                    }
                }
                Picker("Display currency", selection: Binding(
                    get: { store.displayCurrency },
                    set: { store.setDisplayCurrency($0) })) {
                    ForEach(store.availableDisplayCurrencies, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("This month") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Income").font(.caption2).foregroundStyle(.secondary)
                        Text(store.displayMoneyBase(thisMonth.inc)).foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Expense").font(.caption2).foregroundStyle(.secondary)
                        Text(store.displayMoneyBase(thisMonth.exp)).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    /// Compact ledger switcher shown as a popover from the header name — a clean
    /// floating card (one row per ledger, active marked) instead of the Menu.
    private var ledgerPicker: some View {
        VStack(spacing: 0) {
            ForEach(store.ledgers) { l in
                Button {
                    if l.id != store.activeLedgerId { store.activeLedgerId = l.id }
                    showingLedgerPicker = false
                } label: {
                    HStack(spacing: 12) {
                        Text(l.name).foregroundStyle(.primary)
                        Spacer(minLength: 24)
                        if l.id == store.activeLedgerId {
                            Image(systemName: "checkmark").font(.callout.weight(.semibold)).foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if l.id != store.ledgers.last?.id { Divider() }
            }
        }
        .frame(minWidth: 220)
    }
}
