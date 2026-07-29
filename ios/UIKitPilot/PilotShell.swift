import UIKit
import SwiftUI
import FinchCore

// MARK: - UIKit migration pilot (THROWAWAY — never merged)
//
// Purpose: answer three things an estimate cannot, before committing to the plan
// in `ios/docs/uikit-migration-plan.md`.
//
//   1. Does a CONVERTED page actually stop shadowing in THIS app — not just in the
//      minimal reproducer? The pilot pushes the UIKit AccountDetail and the
//      SwiftUI one side by side from the same UIKit root, so it is an A/B rather
//      than a memory of yesterday's build.
//   2. How long does one real screen take against the estimate (AccountDetailView
//      is 320 lines and exercises search, month sections, swipe actions, a
//      toolbar, a context menu and five sheets).
//   3. How bad is the hybrid seam — hosting SwiftUI screens inside a UIKit shell,
//      where `.toolbar` and `.searchable` do not bridge.
//
// It is a SEPARATE TARGET reusing the real FinchStore and models, so FinchApp and
// FinchMac are untouched. Run the `FinchUIKitPilot` scheme.

@main
final class PilotAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // The real store, the real DB, the real demo seed — the pilot is not a mock.
        FinchStore.shared.bootstrap()

        let w = UIWindow(windowScene: windowScene)
        w.rootViewController = PilotTabs()
        w.makeKeyAndVisible()
        window = w
    }
}

/// UIKit root: the shape Phase 1 of the plan would build.
final class PilotTabs: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let accounts = UINavigationController(rootViewController: AccountsListVC())
        accounts.tabBarItem = UITabBarItem(title: "Accounts",
                                           image: UIImage(systemName: "creditcard"), tag: 0)
        let others = [("Budgets", "chart.pie"), ("Scheduled", "calendar"), ("Insights", "chart.line.uptrend.xyaxis")]
            .enumerated().map { i, spec -> UIViewController in
                // Hosted SwiftUI tab roots — exactly how Phase 1 keeps unconverted
                // screens working. Roots never shadow, so these stay as they are.
                let vc = UIViewController()
                vc.view.backgroundColor = .systemBackground
                vc.tabBarItem = UITabBarItem(title: spec.0, image: UIImage(systemName: spec.1), tag: i + 1)
                return vc
            }
        viewControllers = [accounts] + others
    }
}

/// A minimal UIKit accounts list whose only job is to offer the A/B: open the same
/// account through the CONVERTED screen or through the SwiftUI original.
final class AccountsListVC: UITableViewController {
    private var accounts: [AccountRow] = []

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Accounts"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        accounts = FinchStore.shared.accounts
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        accounts = FinchStore.shared.accounts
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }

    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? {
        switch s {
        case 0:  return "Converted — UIKit (expected: NO shadow)"
        case 1:  return "Original — SwiftUI, hosted (expected: shadow)"
        case 2:  return "BISECT — why does the real screen stay clean but a plain List not?"
        default: return "COVERAGE — the app's remaining drill destinations, hosted"
        }
    }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        switch s {
        case 2:  return BisectCase.allCases.count
        case 3:  return DrillDestination.allCases.count
        default: return accounts.count
        }
    }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip)
        if ip.section == 2 {
            let c = BisectCase.allCases[ip.row]
            var cfg = cell.defaultContentConfiguration()
            cfg.text = c.title
            cfg.secondaryText = c.blurb
            cell.contentConfiguration = cfg
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        if ip.section == 3 {
            let d = DrillDestination.allCases[ip.row]
            var cfg = cell.defaultContentConfiguration()
            cfg.text = d.title
            cfg.secondaryText = d.blurb
            cell.contentConfiguration = cfg
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        let a = accounts[ip.row]
        var cfg = cell.defaultContentConfiguration()
        cfg.text = a.name ?? "Account"
        cfg.secondaryText = FinchStore.shared.displayMoney(a.balance, from: a.currency)
        cell.contentConfiguration = cfg
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        if ip.section == 2 {
            let c = BisectCase.allCases[ip.row]
            let host = UIHostingController(rootView: BisectList(kase: c))
            host.title = c.title
            navigationController?.pushViewController(host, animated: true)
            return
        }
        if ip.section == 3 {
            let d = DrillDestination.allCases[ip.row]
            guard let host = d.makeHost() else { return }
            host.title = d.title
            navigationController?.pushViewController(host, animated: true)
            return
        }
        let a = accounts[ip.row]
        if ip.section == 0 {
            navigationController?.pushViewController(AccountDetailVC(accountId: a.id), animated: true)
        } else {
            // The hybrid seam: a hosted SwiftUI screen. Note that its .toolbar and
            // .searchable do NOT reach this navigationItem — the bridging tax the
            // plan budgets for.
            let host = UIHostingController(rootView:
                AccountDetailView(accountId: a.id)
                    .environmentObject(FinchStore.shared)
                    .environmentObject(DeepLinkRouter.shared)
                    .environmentObject(BiometricGate.shared)
            )
            host.title = a.name ?? "Account"
            navigationController?.pushViewController(host, animated: true)
        }
    }
}


/// The real `AccountDetailView`, hosted, does NOT shadow here — but a plain
/// SwiftUI `List` does. Both are hosted identically, so the difference is what the
/// PAGE contributes to the navigation item. `AccountDetailView` has `.searchable`
/// and a `.toolbar`, which bridge into the UIKit `navigationItem`; the plain list
/// contributes nothing and leaves the top edge to SwiftUI.
///
/// If B1/B2/B3 are clean, then in a UIKit shell every hosted SwiftUI page that
/// populates the bar is already clean — which is every real screen in finch — and
/// Phase 1 of the migration plan fixes the bug WITHOUT converting any page.
enum BisectCase: Int, CaseIterable {
    case plain, searchable, toolbar, both, fewRows, realFeed, sectioned, sectionedPlus

    var title: String {
        switch self {
        case .plain:      return "B0 · plain List (known bad)"
        case .searchable: return "B1 · List + .searchable"
        case .toolbar:    return "B2 · List + .toolbar item"
        case .both:       return "B3 · List + both"
        case .fewRows:    return "B4 · List with only 8 rows"
        case .realFeed:   return "B5 · the REAL Activity feed"
        case .sectioned:  return "B6 · 100 rows, in SECTIONS"
        case .sectionedPlus: return "B7 · sections + searchable + toolbar"
        }
    }
    var blurb: String {
        switch self {
        case .plain:      return "Contributes nothing to the nav item. This is the one that shadows."
        case .searchable: return "Bridges a UISearchController into the UIKit bar."
        case .toolbar:    return "Bridges a bar button item into the UIKit bar."
        case .both:       return "What every real finch screen looks like."
        case .fewRows:    return "BARELY SCROLLS. If this is clean while B0 shadows, content VOLUME is the variable — and the A/B was confounded."
        case .realFeed:   return "A real finch screen with enough data to scroll properly. The honest test of the A/B."
        case .sectioned:  return "THE HYPOTHESIS: every real finch list is sectioned; every synthetic one I built was flat."
        case .sectionedPlus: return "Sections plus the bar content — the closest synthetic match to a real screen."
        }
    }
}

private struct BisectList: View {
    let kase: BisectCase
    @State private var query = ""

    var body: some View {
        switch kase {
        case .plain:
            rows
        case .searchable:
            rows.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        case .toolbar:
            rows.toolbar { ToolbarItem(placement: .primaryAction) { Button("Action") {} } }
        case .both:
            rows
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
                .toolbar { ToolbarItem(placement: .primaryAction) { Button("Action") {} } }
        case .fewRows:
            rows
        case .realFeed:
            rows
        case .sectioned:
            rows
        case .sectionedPlus:
            rows
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
                .toolbar { ToolbarItem(placement: .primaryAction) { Button("Action") {} } }
        }
    }

    @ViewBuilder private var rows: some View {
        if kase == .realFeed {
            // The real screen, hosted the same way, but with the whole ledger's
            // transactions rather than one thin account.
            ActivityFeedView()
                .environmentObject(FinchStore.shared)
                .environmentObject(DeepLinkRouter.shared)
                .environmentObject(BiometricGate.shared)
        } else {
            plainRows
        }
    }

    @ViewBuilder private var plainRows: some View {
        if kase == .sectioned || kase == .sectionedPlus {
            // Same 100 rows as B0, but grouped into month-like sections with headers
            // — the one structural thing every real finch list has and none of the
            // earlier synthetic cases did.
            List {
                ForEach(0..<10, id: \.self) { s in
                    Section("Section \(s)") {
                        ForEach(0..<10, id: \.self) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Row \(s * 10 + r)").font(.body)
                                Text("Subtitle for row \(s * 10 + r)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } else {
            List(0..<(kase == .fewRows ? 8 : 100), id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Row \(i)").font(.body)
                    Text("Subtitle for row \(i)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}


// MARK: - Coverage: the app's remaining drill destinations under a UIKit root
//
// AccountDetailView and ActivityFeedView are clean here at 10, 44 and 2,000 rows,
// while every synthetic list shadows. Two screens is not coverage, so this pushes
// the REST of what the app actually drills into. If they are all clean, the
// migration's viability is settled empirically across the app's real surface and
// the decision reduces to cost.
//
// Note on reading the results: a screen with only a handful of rows barely scrolls,
// and this artifact needs content under the bar (8 synthetic rows were clean). Each
// row below says how much content it has, so a "clean" on a thin screen is not
// mistaken for evidence.
enum DrillDestination: Int, CaseIterable {
    case budgetDetail, holdings, scheduledDetail, transactionDetail
    case categories, merchants, tags, rules
    case categoriesWithSearch
    case categoriesConverted

    var title: String {
        switch self {
        case .budgetDetail:      return "Budget detail"
        case .holdings:          return "Holdings"
        case .scheduledDetail:   return "Scheduled detail"
        case .transactionDetail: return "Transaction detail"
        case .categories:        return "PowerTools · Categories"
        case .merchants:         return "PowerTools · Merchants"
        case .tags:              return "PowerTools · Tags"
        case .rules:             return "PowerTools · Rules"
        case .categoriesWithSearch: return "Categories + pinned search drawer"
        case .categoriesConverted:  return "★ Categories CONVERTED to UIKit"
        }
    }

    var blurb: String {
        switch self {
        case .budgetDetail:      return "Real screen. Rows = that budget's transactions."
        case .holdings:          return "Real screen. THIN — few rows, may not scroll enough to judge."
        case .scheduledDetail:   return "Real screen. THIN — few rows."
        case .transactionDetail: return "Real screen. THIN — a form, barely scrolls."
        case .categories:        return "Real screen, ~40 rows in a hierarchy."
        case .merchants:         return "Real screen. Row count grows with the seeded merchants."
        case .tags:              return "Real screen. Usually thin."
        case .rules:             return "Real screen. Usually thin."
        case .categoriesWithSearch: return "Adding a second .searchable — it already had one via SearchableModifier, so this was a no-op."
        case .categoriesConverted:  return "THE DECISIVE TEST: the screen that SHADOWS, converted. Clean = conversion works."
        }
    }

    @MainActor func makeHost() -> UIViewController? {
        let store = FinchStore.shared
        func host<V: View>(_ v: V) -> UIViewController {
            UIHostingController(rootView: v
                .environmentObject(store)
                .environmentObject(DeepLinkRouter.shared)
                .environmentObject(BiometricGate.shared))
        }
        switch self {
        case .budgetDetail:
            guard let id = store.budgets.first?.id else { return nil }
            return host(BudgetDetailView(budgetId: id))
        case .holdings:
            return host(HoldingsView())
        case .scheduledDetail:
            guard let id = store.scheduled.first?.id else { return nil }
            return host(ScheduledDetailView(templateId: id))
        case .transactionDetail:
            guard let id = store.txns.first?.id else { return nil }
            return host(TransactionDetailView(txId: id))
        case .categories: return host(CategoriesView())
        case .merchants:  return host(MerchantsView())
        case .tags:       return host(TagsView())
        case .rules:      return host(RulesManagerView())
        case .categoriesWithSearch:
            // CategoriesView shadows; AccountDetailView and ActivityFeedView do not,
            // and the sharpest structural difference is that both of those carry a
            // permanently pinned search drawer while Categories has no .searchable
            // at all. Add exactly that and nothing else.
            //
            // Caveat on interpreting a clean result: synthetic lists B1/B3 had this
            // same pinned drawer and still shadowed, so the drawer alone was not
            // protective there. A clean result here means it protects in
            // combination with whatever else real screens do — not that the drawer
            // is the mechanism.
            return host(CategoriesWithSearch())
        case .categoriesConverted:
            return CategoriesVC()
        }
    }
}


/// `CategoriesView` plus a pinned search drawer — the single-variable test of the
/// only structural property that separates the clean real screens from the one
/// that shadows.
private struct CategoriesWithSearch: View {
    @State private var query = ""
    var body: some View {
        CategoriesView()
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search")
    }
}
