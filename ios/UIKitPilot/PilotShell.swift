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

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? {
        switch s {
        case 0:  return "Converted — UIKit (expected: NO shadow)"
        case 1:  return "Original — SwiftUI, hosted (expected: shadow)"
        default: return "BISECT — why does the real screen stay clean but a plain List not?"
        }
    }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        s == 2 ? BisectCase.allCases.count : accounts.count
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
    case plain, searchable, toolbar, both

    var title: String {
        switch self {
        case .plain:      return "B0 · plain List (known bad)"
        case .searchable: return "B1 · List + .searchable"
        case .toolbar:    return "B2 · List + .toolbar item"
        case .both:       return "B3 · List + both"
        }
    }
    var blurb: String {
        switch self {
        case .plain:      return "Contributes nothing to the nav item. This is the one that shadows."
        case .searchable: return "Bridges a UISearchController into the UIKit bar."
        case .toolbar:    return "Bridges a bar button item into the UIKit bar."
        case .both:       return "What every real finch screen looks like."
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
        }
    }

    private var rows: some View {
        List(0..<100, id: \.self) { i in
            VStack(alignment: .leading, spacing: 2) {
                Text("Row \(i)").font(.body)
                Text("Subtitle for row \(i)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
