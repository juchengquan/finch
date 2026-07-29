import UIKit
import SwiftUI

// UIKit-ROOT test for the iOS 26 resume shadow.
//
// Everything in finch's lab was a SwiftUI app: the window is rooted in SwiftUI's
// hosting infrastructure, and EVERY push there shadowed — SwiftUI pages (#0, #24,
// #25), a pure UIKit table (#26), even under a real UINavigationController (#20).
// Files and Messages do not shadow, and the one structural thing they have that
// finch cannot have is a UIKit-rooted window.
//
// This app is that: UIApplicationDelegate -> UIWindow -> UITabBarController ->
// UINavigationController, no SwiftUI anywhere above the pushed page. Two pushes:
//
//   A. a pure UIKit UITableView page      — expected clean (this is Files' shape)
//   B. a SwiftUI List in a UIHostingController — THE QUESTION
//
// If A is clean and B is clean  -> a UIKit SHELL is enough; finch's 148 SwiftUI
//                                  views could stay, and a conversion is weeks.
// If A is clean and B shadows   -> pages must be UIKit too; a conversion is a
//                                  full rewrite of the UI layer, months.
// If both shadow                -> converting to UIKit does not fix it at all,
//                                  and the whole question is closed.

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: windowScene)
        w.rootViewController = RootTabs()
        w.makeKeyAndVisible()
        window = w
    }
}

/// A real UITabBarController — the shape Files and Messages have.
final class RootTabs: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let nav = UINavigationController(rootViewController: MenuVC())
        nav.tabBarItem = UITabBarItem(title: "Lab", image: UIImage(systemName: "testtube.2"), tag: 0)

        let others = (2...5).map { i -> UIViewController in
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            vc.tabBarItem = UITabBarItem(title: "Tab \(i)",
                                         image: UIImage(systemName: "\(i).circle"), tag: i)
            return vc
        }
        viewControllers = [nav] + others
    }
}

final class MenuVC: UITableViewController {
    private let rows = [
        ("A · Push a pure UIKit table", "Files' shape. Expected clean."),
        ("B · Push a SwiftUI List (hosted)", "THE QUESTION: is a UIKit shell enough?"),
        ("C · Push a SwiftUI List + .searchable", "Same as B, with a search field in the bar."),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIKit root"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { rows.count }
    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip)
        var cfg = cell.defaultContentConfiguration()
        cfg.text = rows[ip.row].0
        cfg.secondaryText = rows[ip.row].1
        cell.contentConfiguration = cfg
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        switch ip.row {
        case 0:
            navigationController?.pushViewController(UIKitRows(), animated: true)
        case 1:
            let host = UIHostingController(rootView: SwiftUIRows(searchable: false))
            host.title = "SwiftUI list (hosted)"
            navigationController?.pushViewController(host, animated: true)
        default:
            let host = UIHostingController(rootView: SwiftUIRows(searchable: true))
            host.title = "SwiftUI list + search"
            navigationController?.pushViewController(host, animated: true)
        }
    }
}

/// Pure UIKit page — no SwiftUI in the hierarchy at all.
final class UIKitRows: UITableViewController {
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIKit table"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { 100 }
    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip)
        var cfg = cell.defaultContentConfiguration()
        cfg.text = "Row \(ip.row)"
        cfg.secondaryText = "Subtitle for row \(ip.row)"
        cell.contentConfiguration = cfg
        return cell
    }
}

/// SwiftUI page hosted inside the UIKit stack — same content as lab variant 24,
/// which shadowed under a SwiftUI-rooted app.
struct SwiftUIRows: View {
    let searchable: Bool
    @State private var query = ""
    var body: some View {
        if searchable {
            list.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        } else {
            list
        }
    }
    private var list: some View {
        List(0..<100, id: \.self) { i in
            VStack(alignment: .leading, spacing: 2) {
                Text("Row \(i)").font(.body)
                Text("Subtitle for row \(i)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
