#if os(iOS)
import UIKit
import SwiftUI
import Combine
import FinchCore

/// Phase 2, screen 16: `SettingsNotificationsView` converted to UIKit.
///
/// One section: a per-kind toggle for each `NotificationKind`, preceded by a nudge
/// block that appears only when the system permission has been DENIED.
///
/// `kind.title` is already `String(localized:)` on the enum — deliberately, because
/// passing a plain String to `Toggle(_:isOn:)` selects SwiftUI's StringProtocol
/// overload, which does no lookup and rendered these toggles in English in every
/// language. Nothing to fix here; just do not "simplify" it back to a literal.
final class NotificationsSettingsVC: UIViewController {

    private let notifications = NotificationService.shared
    private var cancellables = Set<AnyCancellable>()

    private enum SectionID: Hashable { case kinds, timing }
    private static let deniedID = "__denied__"

    private var collectionView: UICollectionView!
    private static let quietStartID = "__quiet_start__"
    private static let quietEndID = "__quiet_end__"
    private static let deliveryHourID = "__delivery_hour__"

    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Notifications")
        navigationItem.largeTitleDisplayMode = .always
        configureCollectionView()
        configureDataSource()
        applySnapshot()

        // `authorizationDenied` decides whether the nudge block exists at all, and it
        // can flip while the screen is open (the user leaves for iOS Settings and
        // comes back).
        notifications.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySnapshot() }
            .store(in: &cancellables)
    }

    // MARK: Collection view

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
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
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, id in
            // Clear accessories EXCEPT an already-installed switch: removing it from
            // the hierarchy is what destroyed the glass and swallowed taps. See
            // ToggleAccessory.
            if !ToggleAccessory.isInstalled(on: cell) { cell.accessories = [] }

            if id == Self.deniedID {
                // Hosted verbatim: it is a leaf, and the `Link` opens iOS Settings
                // without any UIKit plumbing. The cell is not selectable, so the link
                // keeps its own touches.
                cell.contentConfiguration = UIHostingConfiguration {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Notifications are turned off", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Text("Enable them in iOS Settings to receive budget and scheduled alerts.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url)
                        }
                    }
                }
                return
            }

            if id == Self.quietStartID || id == Self.quietEndID || id == Self.deliveryHourID {
                var cfg = cell.defaultContentConfiguration()
                let quiet = NotificationPrefs.quietHours
                let hour: Int
                switch id {
                case Self.quietStartID:
                    cfg.text = String(localized: "Quiet from"); hour = quiet.startHour
                case Self.quietEndID:
                    cfg.text = String(localized: "Quiet until"); hour = quiet.endHour
                default:
                    cfg.text = String(localized: "Delivery time"); hour = NotificationPrefs.deliveryHour
                }
                cell.contentConfiguration = cfg
                cell.accessories = [self.hourAccessory(hour: hour) { picked in
                    switch id {
                    case Self.quietStartID:
                        NotificationPrefs.quietHours = QuietHours(startHour: picked, endHour: quiet.endHour)
                    case Self.quietEndID:
                        NotificationPrefs.quietHours = QuietHours(startHour: quiet.startHour, endHour: picked)
                    default:
                        NotificationPrefs.deliveryHour = picked
                    }
                    self.applySnapshot()
                    // The preference alone changes nothing already scheduled — only a
                    // refresh re-triggers what is pending, same as the toggles above.
                    Task { await NotificationService.shared.refresh() }
                }]
                return
            }

            guard let kind = NotificationKind(rawValue: id) else { return }
            var cfg = cell.defaultContentConfiguration()
            cfg.text = kind.title      // already localized on the enum
            cell.contentConfiguration = cfg

            ToggleAccessory.install(on: cell, isOn: NotificationPrefs.isOn(kind)) { on in
                NotificationPrefs.set(kind, on: on)
                // Rescheduling is what actually adds or removes the pending
                // notifications; the preference alone changes nothing.
                Task { await NotificationService.shared.refresh() }
            }
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
    }

    /// A pull-down of the 24 hours, as `SecuritySettingsVC` does for its timeout —
    /// `MenuValueButton` draws the chevron, without which the row reads as a plain
    /// value and nothing says it opens a menu.
    private func hourAccessory(hour: Int, onPick: @escaping (Int) -> Void) -> UICellAccessory {
        let button = MenuValueButton.make(value: Self.hourLabel(hour))
        button.menu = UIMenu(children: (0..<24).map { h in
            UIAction(title: Self.hourLabel(h), state: h == hour ? .on : .off) { _ in onPick(h) }
        })
        return .customView(configuration: .init(customView: button, placement: .trailing()))
    }

    /// Shared with the SwiftUI screen — two formatters is how the two drift apart.
    static func hourLabel(_ hour: Int) -> String { NotificationsSettingsHour.label(hour) }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()
        snap.appendSections([.kinds])
        var items: [String] = []
        if notifications.authorizationDenied { items.append(Self.deniedID) }
        items += NotificationKind.allCases.map(\.rawValue)
        snap.appendItems(items, toSection: .kinds)

        snap.appendSections([.timing])
        snap.appendItems([Self.quietStartID, Self.quietEndID, Self.deliveryHourID], toSection: .timing)

        // Each toggle reads its preference under a fixed identifier.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        dataSource.apply(snap, animatingDifferences: false)
    }
}

extension NotificationsSettingsVC: UICollectionViewDelegate {
    /// A tap anywhere on a kind row flips its switch, matching SwiftUI's `Toggle`.
    /// The denied-permission nudge is not selectable — its `Link` owns its touches.
    /// NOTHING here is row-selectable. Switch rows are flipped by their SWITCH only —
    /// Settings.app behaviour, see `ToggleAccessory` — and the other controls own their
    /// own touches. This must stay rather than be deleted: list rows are selectable by
    /// default, and returning false is also what suppresses the grey selection flash.
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        false
    }
}
#endif
