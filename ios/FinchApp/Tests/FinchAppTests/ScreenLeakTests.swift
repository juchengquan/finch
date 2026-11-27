import XCTest
import UIKit
import FinchCore
@testable import FinchApp

/// A screen that is closed must go away. Cells that host SwiftUI keep their content
/// closures for as long as the cell lives, and the cell lives in the screen's own
/// collection view, so a closure holding the screen strongly kept it alive for good.
/// Every write then rebuilt the dead copies too: they still observed the store.
@MainActor
final class ScreenLeakTests: XCTestCase {

    override func setUp() async throws {
        let store = try await SharedStoreFixture.load()
        // The sample pack has no budget, and the budget screen needs one.
        try store.apply(.createBudget, Args([
            "ledgerId": .string(store.activeLedgerId), "name": .string("Groceries"),
            "amount": .double(400), "frequency": .string("monthly")]))
    }

    /// Show `make()` in a window long enough to lay out its cells, close it, and
    /// report whether it was freed.
    private func isReleased(_ make: () -> UIViewController, prepare: (UIViewController) -> Void = { _ in }) -> Bool {
        weak var probe: UIViewController?
        autoreleasepool {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let vc = make()
            probe = vc
            let nav = UINavigationController(rootViewController: vc)
            window.rootViewController = nav
            window.makeKeyAndVisible()
            nav.view.layoutIfNeeded()
            prepare(vc)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            nav.view.layoutIfNeeded()
            window.isHidden = true
            window.rootViewController = nil
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return probe == nil
    }

    func test_closedScreensAreFreed() throws {
        let store = FinchStore.shared
        let account = try XCTUnwrap(store.accounts.first)
        let budget = try XCTUnwrap(store.budgets.first)
        let ledger = try XCTUnwrap(store.ledgers.first)
        let category = try XCTUnwrap(store.categories.first)
        let screens: [(String, () -> UIViewController)] = [
            ("AccountDetailVC", { AccountDetailVC(accountId: account.id) }),
            ("ActivityFeedVC", { ActivityFeedVC() }),
            ("ScheduledListVC", { ScheduledListVC() }),
            ("AccountsListVC", { AccountsListVC() }),
            ("BudgetsListVC", { BudgetsListVC() }),
            ("BudgetDetailVC", { BudgetDetailVC(budgetId: budget.id) }),
            ("CategoriesVC", { CategoriesVC() }),
            ("TagsVC", { TagsVC() }),
            ("MerchantsVC", { MerchantsVC() }),
            ("LedgersVC", { LedgersVC() }),
            ("LedgerDetailVC", { LedgerDetailVC(ledgerId: ledger.id) }),
            ("TxListDetailVC", { TxListDetailVC(.category(category)) }),
            ("SettingsListVC", { SettingsListVC() }),
            ("AppearanceSettingsVC", { AppearanceSettingsVC() }),
            ("BackupSyncSettingsVC", { BackupSyncSettingsVC() }),
            ("BackupsVC", { BackupsVC() }),
            ("NotificationsSettingsVC", { NotificationsSettingsVC() }),
            ("ExchangeRateHistoryVC", { ExchangeRateHistoryVC(currency: "EUR") }),
            ("CurrenciesVC", { CurrenciesVC() }),
        ]
        var kept: [String] = []
        for (name, make) in screens where !isReleased(make) { kept.append(name) }
        XCTAssertEqual(kept, [], "closed screens still alive")
    }

    /// The frequency row exists only once a backup folder is chosen, so the list
    /// above never builds it — and its menu held the screen.
    func test_backupsWithAFolderIsFreed() throws {
        let key = "finch.backupFolder.bookmark"
        let saved = UserDefaults.standard.data(forKey: key)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("leak-test-backups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            ICloudSync.shared.clearFolder()
            if let saved { UserDefaults.standard.set(saved, forKey: key); ICloudSync.shared.refresh() }
            try? FileManager.default.removeItem(at: folder)
        }
        ICloudSync.shared.setFolder(folder)
        XCTAssertNotNil(ICloudSync.shared.designatedFolderName, "the folder rows need a folder")
        XCTAssertTrue(isReleased { BackupsVC() }, "BackupsVC with a folder still alive")
    }
}
