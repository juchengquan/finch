#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 17: `SettingsSecurityView` converted to UIKit.
///
/// One section, three rows, two of them conditional: the lock policy, a timeout that
/// only applies to the two delayed policies, and a Face-ID-for-destructive-actions
/// toggle that only exists while locking is on at all.
///
/// SECURITY-SENSITIVE. Every write goes through `gate.settings`, exactly as the
/// SwiftUI screen did — `BiometricGate` persists on `didSet`, so assigning the
/// struct's property IS the save. Nothing here reimplements the policy, and the
/// enum's `displayName` is reused rather than re-spelled, so a new policy case
/// cannot silently render blank.
final class SecuritySettingsVC: UIViewController {

    private let gate = BiometricGate.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case lock }
    private static let policyID = "__policy__"
    private static let timeoutID = "__timeout__"
    private static let sensitiveID = "__sensitive__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!

    /// The offered timeouts, matching the SwiftUI picker.
    private static let timeouts = [60, 300, 900, 1800, 3600]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Security")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        gate.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        config.footerMode = .supplementary
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
            // Clear accessories EXCEPT an already-installed switch: removing it from
            // the hierarchy is what destroyed the glass and swallowed taps. See
            // ToggleAccessory.
            if !ToggleAccessory.isInstalled(on: cell) { cell.accessories = [] }
            var cfg = cell.defaultContentConfiguration()

            switch id {
            case Self.policyID:
                cfg.text = String(localized: "App lock")
                cell.contentConfiguration = cfg
                let current = self.gate.settings.policy
                cell.accessories = [self.menuAccessory(
                    value: current.displayName,
                    options: BiometricPolicy.allCases.map { ($0.displayName, $0.rawValue) },
                    onPick: { [weak self] raw in
                        guard let policy = BiometricPolicy(rawValue: raw) else { return }
                        self?.gate.settings.policy = policy
                    })]

            case Self.timeoutID:
                cfg.text = String(localized: "Lock after")
                cell.contentConfiguration = cfg
                let current = self.gate.settings.timeoutSeconds
                cell.accessories = [self.menuAccessory(
                    value: Self.minutesLabel(current),
                    options: Self.timeouts.map { (Self.minutesLabel($0), "\($0)") },
                    onPick: { [weak self] raw in
                        guard let seconds = Int(raw) else { return }
                        self?.gate.settings.timeoutSeconds = seconds
                    })]

            case Self.sensitiveID:
                cfg.text = String(localized: "Require Face ID for export & destructive actions")
                cell.contentConfiguration = cfg
                ToggleAccessory.install(on: cell,
                                        isOn: self.gate.settings.sensitiveActionsEnabled) { [weak self] on in
                    self?.gate.settings.sensitiveActionsEnabled = on
                }

            default:
                break
            }
        }

        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { view, _, _ in
            var cfg = view.defaultContentConfiguration()
            cfg.text = String(localized: "Uses Face ID / Touch ID, falling back to your device passcode. finch never stores a passcode of its own.")
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
        }
    }

    private static func minutesLabel(_ seconds: Int) -> String {
        String(localized: "\(seconds / 60) min")
    }

    /// A pull-down menu button, as SwiftUI's default `Picker` renders inside a form.
    private func menuAccessory(value: String, options: [(String, String)],
                               onPick: @escaping (String) -> Void) -> UICellAccessory {
        let button = UIButton(type: .system)
        button.setTitle(value, for: .normal)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: options.map { title, raw in
            UIAction(title: title, state: title == value ? .on : .off) { _ in onPick(raw) }
        })
        return .customView(configuration: .init(customView: button, placement: .trailing()))
    }

    private func applySnapshot() {
        let policy = gate.settings.policy
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.lock])
        var items = [Self.policyID]
        // A timeout only means something for the two delayed policies.
        if policy == .onBackground || policy == .onIdle { items.append(Self.timeoutID) }
        // And re-prompting for destructive actions only if locking is on at all.
        if policy != .off { items.append(Self.sensitiveID) }
        snap.appendItems(items, toSection: .lock)

        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))
        dataSource.apply(snap, animatingDifferences: false)
    }
}

extension SecuritySettingsVC: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }
}
#endif
