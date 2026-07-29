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

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? {
        s == 0 ? "Converted — UIKit (expected: NO shadow)" : "Original — SwiftUI, hosted (expected: shadow)"
    }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { accounts.count }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip)
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
