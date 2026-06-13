import SwiftUI
import FinchCore

/// Accounts grouped by account group, each section with a subtotal, plus a
/// net-worth footer (includeInNetWorth == 1). All amounts convert
/// account-currency → base → display via Money. Detail view deferred (D4) —
/// rows are NOT NavigationLinks in Phase 1.0.
struct AccountsTab: View {
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    EmptyState(tab: .accounts)
                } else {
                    List {
                        ForEach(store.accountGroupsOrdered, id: \.self) { groupName in
                            Section {
                                ForEach(store.accounts(in: groupName)) { account in
                                    AccountRowView(account: account)
                                }
                            } header: {
                                HStack {
                                    Text(groupName)
                                    Spacer()
                                    Text(store.subtotalDisplay(for: groupName))
                                }
                            }
                        }
                        Section {
                            HStack {
                                Text("Net worth").fontWeight(.semibold)
                                Spacer()
                                Text(store.netWorthDisplay).fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { HoldingsView() } label: { Image(systemName: "chart.bar") }
                        .accessibilityLabel("Holdings")
                }
            }
        }
    }
}

struct AccountRowView: View {
    @EnvironmentObject private var store: FinchStore
    let account: AccountRow
    var body: some View {
        HStack {
            Image(systemName: AccountTypeIcon.icon(for: account.type))
                .foregroundStyle(.secondary)
            Text(account.name ?? "—")
            Spacer()
            Text(store.displayMoney(account.balance, from: account.currency))
                .fontWeight(.semibold)
        }
    }
}
