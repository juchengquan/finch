#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 14: `RulesManagerView` converted to UIKit.
///
/// The last hosted SwiftUI screen that sat inside a pushed page. With this landed,
/// nothing reachable from a converted list is a hosted SwiftUI scroll view in a
/// push — the shape that reproduces the iOS 26 resume shadow.
///
/// Only the LIST is converted. `RuleSheet` and `RuleDetailView` (the bulk of the
/// SwiftUI file) stay SwiftUI: they are presented, never pushed, so they cannot
/// shadow and there is nothing to gain from porting them.
///
/// Two details are unique to this screen among the converted set:
///   - it has a LEADING swipe action (Backfill) that is not part of the shared
///     `TxRowActions`, because these are rules rather than transactions;
///   - tapping a row opens one of TWO different sheets, decided by whether the
///     rule can be round-tripped through the editor: `RuleParse.parse` succeeding
///     means it uses CP1 fields and is editable, failing means it uses CP2 fields,
///     nested groups, `not` or splits and opens READ-ONLY. Sending an unparseable
///     rule to the editor would silently rewrite it on save.
final class RulesManagerVC: UIViewController {

    private let store = FinchStore.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case rules }
    private static let emptyID = "__empty__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var ruleByID: [String: RuleSummary] = [:]
    private var counts: [String: Int] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Rules")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        configureToolbar()
        applySnapshot()

        // `rules` is an @Published slice, but the match counts derive from `txns`, and
        // a backfill changes those without touching the rule rows.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.trailingSwipe(at: indexPath)
        }
        config.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.leadingSwipe(at: indexPath)
        }
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
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

            if id == Self.emptyID {
                var cfg = cell.defaultContentConfiguration()
                cfg.text = String(localized: "No rules yet. Rules auto-apply to new income/expense entries.")
                cfg.textProperties.color = .secondaryLabel
                cell.contentConfiguration = cfg
                return
            }

            guard let rule = self.ruleByID[id] else { return }
            var cfg = cell.defaultContentConfiguration()
            cfg.text = rule.name
            cfg.secondaryText = String(localized: "priority \(rule.priority)")
            cfg.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption2)
            cell.contentConfiguration = cfg

            var accessories: [UICellAccessory] = []
            // The match count is hidden at zero, as in SwiftUI — a rule that has never
            // matched shows nothing rather than a "0×" that reads like a failure.
            if let n = self.counts[rule.id], n > 0 {
                let label = UILabel()
                // Through the catalog, not a bare literal: the SwiftUI screen's
                // `Text("\(n)×")` already contributes the key "%lld×", so this reuses
                // it rather than shipping an unextractable string.
                label.text = String(localized: "\(n)×")
                label.font = UIFont.monospacedDigitSystemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
                label.textColor = .secondaryLabel
                label.accessibilityLabel = String(localized: "\(n) transactions")
                accessories.append(.customView(configuration: .init(customView: label,
                                                                    placement: .trailing())))
            }
            // A UISwitch accessory rather than hosted SwiftUI: it must take its own
            // touches while the row stays tappable for the editor.
            let toggle = UISwitch()
            toggle.isOn = rule.isActive
            toggle.accessibilityLabel = String(localized: "Active")
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let on = toggle?.isOn else { return }
                self.setActive(rule, on)
            }, for: .valueChanged)
            accessories.append(.customView(configuration: .init(customView: toggle,
                                                                placement: .trailing())))
            cell.accessories = accessories
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    private func applySnapshot() {
        counts = Selectors.ruleMatchCounts(store.txns, store.activeLedgerId)
        let rules = store.rules
        ruleByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })

        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.rules])
        snap.appendItems(rules.isEmpty ? [Self.emptyID] : rules.map(\.id), toSection: .rules)

        // A rename, a priority change, an active flip or a backfill's new match count
        // all leave the identifiers alone.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Bar and gestures

    private func configureToolbar() {
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                  primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.present(self.hosted(RuleSheet(rule: nil)), animated: true)
        })
        add.accessibilityLabel = String(localized: "Add rule")
        navigationItem.rightBarButtonItems = [add]
    }

    private func trailingSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let rule = ruleByID[id] else { return nil }
        // Not `.destructive`: the alert confirms first.
        let delete = UIContextualAction(style: .normal, title: String(localized: "Delete")) { [weak self] _, _, done in
            self?.confirmDelete(rule); done(false)
        }
        delete.image = UIImage(systemName: "trash")
        delete.backgroundColor = .systemRed
        return UISwipeActionsConfiguration(actions: [delete])
    }

    /// Backfill on the LEADING edge, matching the SwiftUI screen. It applies the rule
    /// to existing transactions, so it is a write — but a re-runnable one, which is
    /// why it needs no confirmation.
    private func leadingSwipe(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let rule = ruleByID[id] else { return nil }
        let backfill = UIContextualAction(style: .normal, title: String(localized: "Backfill")) { [weak self] _, _, done in
            self?.backfill(rule); done(true)
        }
        backfill.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        backfill.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [backfill])
    }

    // MARK: Writes

    private func run(_ work: () throws -> Void) {
        do { try work() } catch {
            let alert = UIAlertController(title: String(localized: "Data problem"),
                                          message: i18nMessage(error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
            present(alert, animated: true)
        }
    }

    private func setActive(_ rule: RuleSummary, _ on: Bool) {
        run {
            try store.apply(.updateRule, Args(["id": .string(rule.id),
                                               "patch": .object(["isActive": .bool(on)])]))
        }
        applySnapshot()   // put the switch back if the write was refused
    }

    private func backfill(_ rule: RuleSummary) {
        run { try store.apply(.backfillRule, Args(["id": .string(rule.id)])) }
    }

    private func confirmDelete(_ rule: RuleSummary) {
        let alert = UIAlertController(title: String(localized: "Delete rule?"),
                                      message: String(localized: "This permanently deletes the rule."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try self.store.apply(.deleteRule, Args(["id": .string(rule.id)])) }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: Sheets — SwiftUI, hosted. Presented, so they never shadow.

    private func hosted<V: View>(_ view: V) -> UIViewController {
        UIHostingController(rootView: view
            .environmentObject(store)
            .environmentObject(DeepLinkRouter.shared)
            .environmentObject(BiometricGate.shared))
    }

    /// Editable only if the rule round-trips through the editor's model. A rule using
    /// CP2 fields, nested groups, `not` or splits opens READ-ONLY — handing it to the
    /// editor would silently rewrite it on save.
    private func open(_ rule: RuleSummary) {
        let editable = RuleParse.parse(conditionJSON: rule.conditionJSON,
                                       actionsJSON: rule.actionsJSON) != nil
        present(hosted(editable ? AnyView(RuleSheet(rule: rule))
                                : AnyView(RuleDetailView(rule: rule))), animated: true)
    }
}

extension RulesManagerVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return ruleByID[id] != nil
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let rule = ruleByID[id] else { return }
        open(rule)
    }

    func collectionView(_ cv: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let rule = ruleByID[id] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Backfill"),
                         image: UIImage(systemName: "arrow.triangle.2.circlepath")) { _ in
                    self?.backfill(rule)
                },
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in self?.confirmDelete(rule) },
            ])
        }
    }
}
#endif
