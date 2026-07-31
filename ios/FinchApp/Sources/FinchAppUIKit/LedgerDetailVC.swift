#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// `LedgerDetailView` converted to UIKit — layer 2 of the ledger flow.
///
/// Ships with `LedgersVC` and not after it: a native list pushing a hosted SwiftUI
/// detail is reproducer B (a hosted scroll view at navigation depth), so converting
/// the list alone would have introduced the resume shadow on a flow that never had it.
///
/// Reads any ledger by id — the active one from live state, others through
/// `ledgerSummary` — so a non-active ledger can be inspected without switching the
/// app out from under the user. Pops if the ledger is deleted elsewhere.
final class LedgerDetailVC: UIViewController {

    private let ledgerId: String
    private let store = FinchStore.shared
    private let gate = BiometricGate.shared
    private let router = DeepLinkRouter.shared
    private var cancellables = Set<AnyCancellable>()

    private var summary: FinchStore.LedgerSummary?
    private var ledger: Ledger? { store.ledgers.first { $0.id == ledgerId } }
    private var isActive: Bool { ledgerId == store.activeLedgerId }

    private enum SectionID: Hashable { case summary, accounts, currency, actions, activity }
    private static let netWorthID = "__net_worth__"
    private static let monthID = "__month__"
    private static let currencyID = "__currency__"
    private static let makeActiveID = "__make_active__"
    private static let editID = "__edit__"
    private static let deleteID = "__delete__"
    private static let activityID = "__activity__"
    private static let accountPrefix = "__acct__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var headers: [SectionID: String] = [:]
    private var accountByID: [String: AccountRow] = [:]

    init(ledgerId: String) {
        self.ledgerId = ledgerId
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ledger?.name
        // Inline, as the SwiftUI screen sets explicitly — this is a drill-in, and the
        // ledger name is short enough that a large title only costs vertical space.
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        reloadSummary()

        store.$ledgers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // The ledger can be deleted from elsewhere (another device, the list
                // behind us). The SwiftUI screen dismissed; same rule here.
                guard let ledger = self.ledger else {
                    self.navigationController?.popViewController(animated: true)
                    return
                }
                self.title = ledger.name
                self.applySnapshot()
            }
            .store(in: &cancellables)
        // The month figures come from the transactions.
        store.$txns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadSummary() }
            .store(in: &cancellables)
        store.$activeLedgerId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }   // Make-active row appears/disappears
            .store(in: &cancellables)
    }

    private func reloadSummary() {
        summary = store.ledgerSummary(ledgerId)
        applySnapshot()
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let section = self?.dataSource.sectionIdentifier(for: index)
            config.headerMode = (section.map { self?.headers[$0] != nil } ?? false) ? .supplementary : .none
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            guard let self else { return }
            cell.accessories = []
            var cfg = cell.defaultContentConfiguration()

            switch id {
            case Self.netWorthID:
                cfg.text = String(localized: "Net worth")
                cfg.textProperties.font = .preferredFont(forTextStyle: .caption1)
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg
                if let s = self.summary {
                    let v = UILabel()
                    v.text = self.store.displayMoney(s.netWorth, forLedger: self.ledgerId)
                    v.font = .preferredFont(forTextStyle: .headline)
                    cell.accessories = [.customView(configuration: .init(customView: v, placement: .trailing()))]
                }

            case Self.monthID:
                // Hosted: `StatusSummaryRow` is a leaf, and it is the same two-column
                // income/expense row the rest of the app uses. Rebuilding it here would
                // be a second copy to keep in step for no gain.
                if let s = self.summary {
                    cell.contentConfiguration = UIHostingConfiguration {
                        StatusSummaryRow(
                            leadingLabel: "Income",
                            leadingValue: self.store.displayMoney(s.monthIncome, forLedger: self.ledgerId),
                            trailingLabel: "Expense",
                            trailingValue: self.store.displayMoney(s.monthExpense, forLedger: self.ledgerId))
                    }
                }

            case Self.currencyID:
                cfg.text = String(localized: "Display currency")
                cell.contentConfiguration = cfg
                let current = self.store.displayCurrency(forLedger: self.ledgerId)
                cell.accessories = [self.menuAccessory(
                    value: current,
                    options: self.store.availableDisplayCurrencies(forLedger: self.ledgerId),
                    onPick: { [weak self] code in
                        guard let self else { return }
                        self.store.setDisplayCurrency(code, ledgerId: self.ledgerId)
                        self.reloadSummary()
                    })]

            case Self.makeActiveID:
                cfg.text = String(localized: "Make active ledger")
                cfg.textProperties.color = .tintColor
                cell.contentConfiguration = cfg

            case Self.editID:
                cfg.text = String(localized: "Edit")
                cfg.textProperties.color = .tintColor
                cell.contentConfiguration = cfg

            case Self.deleteID:
                cfg.text = String(localized: "Delete")
                // Disabled at one ledger, like the SwiftUI button — greyed rather than
                // hidden so the action's absence is explained by its state.
                cfg.textProperties.color = self.store.ledgers.count > 1 ? .systemRed : .tertiaryLabel
                cell.contentConfiguration = cfg

            case Self.activityID:
                cfg.text = String(localized: "View all activity")
                cfg.image = UIImage(systemName: "list.bullet")
                cfg.textProperties.color = .tintColor
                cell.contentConfiguration = cfg
                cell.accessories = [.disclosureIndicator()]

            default:
                guard let account = self.accountByID[id] else { return }
                cfg.text = account.name ?? "—"
                cell.contentConfiguration = cfg
                let base = self.store.baseCurrency(forLedger: self.ledgerId)
                let v = UILabel()
                v.text = self.store.displayMoney(
                    self.store.toBase(account.balance, from: account.currency, ledgerBase: base),
                    forLedger: self.ledgerId)
                v.font = .preferredFont(forTextStyle: .body)
                v.textColor = .secondaryLabel
                cell.accessories = [.customView(configuration: .init(customView: v, placement: .trailing()))]
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, let section = self.dataSource.sectionIdentifier(for: indexPath.section),
                  let text = self.headers[section] else { return }
            var cfg = view.defaultContentConfiguration()
            cfg.text = text
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    /// A pull-down menu button, as SwiftUI's default `Picker` renders inside a form.
    private func menuAccessory(value: String, options: [String],
                               onPick: @escaping (String) -> Void) -> UICellAccessory {
        let button = MenuValueButton.make(value: value)
        button.menu = UIMenu(children: options.map { code in
            UIAction(title: code, state: code == value ? .on : .off) { _ in onPick(code) }
        })
        return .customView(configuration: .init(customView: button, placement: .trailing()))
    }

    private func applySnapshot() {
        guard ledger != nil else { return }
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        headers = [:]

        if summary != nil {
            snap.appendSections([.summary])
            snap.appendItems([Self.netWorthID, Self.monthID], toSection: .summary)
            headers[.summary] = String(localized: "This month")
        }
        if let accounts = summary?.accounts, !accounts.isEmpty {
            accountByID = Dictionary(uniqueKeysWithValues: accounts.map { (Self.accountPrefix + $0.id, $0) })
            snap.appendSections([.accounts])
            snap.appendItems(accounts.map { Self.accountPrefix + $0.id }, toSection: .accounts)
            headers[.accounts] = String(localized: "Accounts")
        }
        snap.appendSections([.currency])
        snap.appendItems([Self.currencyID], toSection: .currency)

        snap.appendSections([.actions])
        var actions: [String] = []
        if !isActive { actions.append(Self.makeActiveID) }   // no point offering it on the active one
        actions += [Self.editID, Self.deleteID]
        snap.appendItems(actions, toSection: .actions)

        // The feed is only meaningful for the ledger the app is actually scoped to.
        if isActive {
            snap.appendSections([.activity])
            snap.appendItems([Self.activityID], toSection: .activity)
        }

        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Actions

    private func makeActive() {
        do {
            try store.apply(.setDefaultLedger, Args(["id": .string(ledgerId)]))
            store.activeLedgerId = ledgerId
        } catch { presentError(i18nMessage(error)) }
    }

    private func presentEdit(_ ledger: Ledger) {
        present(UIHostingController(rootView:
            EditLedgerSheet(ledger: ledger)
                .environmentObject(store)
                .environmentObject(gate)), animated: true)
    }

    private func confirmDelete(_ ledger: Ledger, from cell: UICollectionViewCell?) {
        let sheet = UIAlertController(title: String(localized: "Delete this ledger?"),
                                      message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            self?.delete(ledger)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        // Anchored on the row — iOS 26 positions popouts at their source, and an
        // unanchored action sheet on iPad has nowhere to point.
        sheet.popoverPresentationController?.sourceView = cell ?? view
        sheet.popoverPresentationController?.sourceRect = (cell ?? view).bounds
        present(sheet, animated: true)
    }

    private func delete(_ ledger: Ledger) {
        Task { @MainActor in
            guard await gate.confirmSensitive() else { return }
            do {
                try store.apply(.deleteLedger, Args(["id": .string(ledger.id)]))
                if store.activeLedgerId == ledger.id {
                    store.activeLedgerId = store.ledgers.first?.id ?? ""
                }
                navigationController?.popViewController(animated: true)
            } catch { presentError(i18nMessage(error)) }
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

extension LedgerDetailVC: UICollectionViewDelegate {
    /// Only the action rows and the activity link do anything; the summary, the
    /// account rows and the currency menu are not selectable.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        if id == Self.deleteID { return store.ledgers.count > 1 }
        return [Self.makeActiveID, Self.editID, Self.activityID].contains(id)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let ledger else { return }
        switch id {
        case Self.makeActiveID: makeActive()
        case Self.editID:       presentEdit(ledger)
        case Self.deleteID:     confirmDelete(ledger, from: cv.cellForItem(at: indexPath))
        case Self.activityID:   navigationController?.pushViewController(ActivityFeedVC(), animated: true)
        default: break
        }
    }
}
#endif
