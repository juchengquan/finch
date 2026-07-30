#if os(iOS)
import UIKit
import SwiftUI
import FinchCore

/// Phase 2, screen 15: `SettingsAppearanceView` converted to UIKit.
///
/// A settings FORM rather than a list — eight sections of toggles and pickers over
/// `@AppStorage`, with two conditional rows (the text-size slider, the FAB position)
/// and two footers whose text changes with state.
///
/// Nothing here shadows: the screen is reached through a cover in the SwiftUI shell
/// and a push here, and it was never a reproducer-B page. This conversion is about
/// finishing the tab, not fixing a bug.
///
/// Compound controls stay SwiftUI, hosted as leaves — the segmented pickers, the
/// A—slider—A row and the live type sample. Rebuilding those in UIKit would be more
/// code AND would drift from the type-size preview, which has to render at the
/// chosen `dynamicTypeSize` to be worth showing at all. Plain toggles are UISwitch
/// accessories, and the two menu pickers are pull-down `UIButton` menus, which is
/// what SwiftUI's default `Picker` renders as inside a form.
final class AppearanceSettingsVC: UIViewController {

    // The same defaults keys the SwiftUI screen bound through @AppStorage. Read and
    // written directly here, since there is no view-update system to invalidate.
    private enum Key {
        static let appearance = "finch.appearance"
        static let language = "finch.language"
        static let groupByMonth = "finch.feed.groupByMonth"
        static let relativeDates = "finch.feed.relativeDates"
        static let showAdjust = "finch.addSheet.showAdjustBalance"
        static let fabEnabled = "finch.fab.enabled"
        static let fabPosition = "finch.fab.position"
    }

    private let defaults = UserDefaults.standard
    /// Set once the language changes, which turns the footer orange.
    private var showRelaunchNote = false

    private enum SectionID: Hashable {
        case theme, textSize, language, activityFeed, accounts, haptics, addSheet, quickAdd
    }

    private static let appearancePickerID = "__appearance__"
    private static let systemSizeID = "__system_size__"
    private static let sliderID = "__size_slider__"
    private static let sampleID = "__size_sample__"
    private static let languageID = "__language__"
    private static let groupByMonthID = "__group_by_month__"
    private static let relativeDatesID = "__relative_dates__"
    private static let reconcileID = "__reconcile__"
    private static let hapticsID = "__haptics__"
    private static let adjustID = "__adjust__"
    private static let fabID = "__fab__"
    private static let fabPositionID = "__fab_position__"

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SectionID, String>!
    private var sectionIDs: [SectionID] = []

    // MARK: Preference accessors — absent key means the SwiftUI default.

    private var useSystemTextSize: Bool { defaults.object(forKey: TextSize.systemKey) as? Bool ?? true }
    private var textSizeStep: Int { defaults.object(forKey: TextSize.stepKey) as? Int ?? TextSize.defaultStep }
    private var groupByMonth: Bool { defaults.object(forKey: Key.groupByMonth) as? Bool ?? true }
    private var relativeDates: Bool { defaults.object(forKey: Key.relativeDates) as? Bool ?? true }
    private var hapticsEnabled: Bool { defaults.object(forKey: Haptics.enabledKey) as? Bool ?? true }
    private var showAdjustInAddSheet: Bool { defaults.bool(forKey: Key.showAdjust) }
    private var fabEnabled: Bool { defaults.object(forKey: Key.fabEnabled) as? Bool ?? true }
    private var fabPositionRaw: String { defaults.string(forKey: Key.fabPosition) ?? FabPosition.right.rawValue }
    private var appearanceRaw: String { defaults.string(forKey: Key.appearance) ?? AppearancePreference.system.rawValue }
    private var languageRaw: String { defaults.string(forKey: Key.language) ?? AppLanguage.system.rawValue }
    private var reconcileStaleDays: Int {
        defaults.object(forKey: ReconcileReminder.key) as? Int ?? ReconcileReminder.defaultDays
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Appearance & Language")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    // MARK: Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            let kind: SectionID? = self?.sectionIDs.indices.contains(index) == true
                ? self?.sectionIDs[index] : nil
            // Two sections are footer-only (haptics, add-sheet) — the SwiftUI screen
            // gives them no header either.
            config.headerMode = (kind == .haptics || kind == .addSheet) ? .none : .supplementary
            config.footerMode = (kind == .theme) ? .none : .supplementary
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

            switch id {
            case Self.appearancePickerID:
                cell.contentConfiguration = UIHostingConfiguration {
                    Picker("", selection: Binding(
                        get: { self.appearanceRaw },
                        set: { self.write(Key.appearance, $0) })) {
                        ForEach(AppearancePreference.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

            case Self.systemSizeID:
                self.configureToggleRow(cell, String(localized: "Use system size"),
                                        isOn: self.useSystemTextSize) { [weak self] on in
                    self?.write(TextSize.systemKey, on)
                }

            case Self.sliderID:
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack(spacing: 12) {
                        Text("A").font(.footnote).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(self.textSizeStep) },
                                              set: { self.write(TextSize.stepKey, Int($0.rounded())) }),
                               in: 0...Double(TextSize.steps.count - 1), step: 1)
                            .accessibilityLabel("Text size")
                        Text("A").font(.title3).foregroundStyle(.secondary)
                    }
                }

            case Self.sampleID:
                // Must render AT the chosen size — that is the whole point of it.
                let step = self.textSizeStep
                cell.contentConfiguration = UIHostingConfiguration {
                    Text("Sample — $1,234.56").dynamicTypeSize(TextSize.size(forStep: step))
                }

            case Self.languageID:
                let current = AppLanguage(rawValue: self.languageRaw) ?? .system
                self.configureMenuRow(cell, String(localized: "Language"), value: current.label,
                                      options: AppLanguage.allCases.map { ($0.label, $0.rawValue) }) { [weak self] raw in
                    self?.setLanguage(raw)
                }

            case Self.groupByMonthID:
                self.configureToggleRow(cell, String(localized: "Group by month"),
                                        isOn: self.groupByMonth) { [weak self] on in
                    self?.write(Key.groupByMonth, on)
                }

            case Self.relativeDatesID:
                self.configureToggleRow(cell, String(localized: "Relative dates"),
                                        isOn: self.relativeDates) { [weak self] on in
                    self?.write(Key.relativeDates, on)
                }

            case Self.reconcileID:
                let days = self.reconcileStaleDays
                let label = days == 0 ? String(localized: "Off") : String(localized: "\(days) days")
                let options = ReconcileReminder.options.map { d -> (String, String) in
                    (d == 0 ? String(localized: "Off") : String(localized: "\(d) days"), "\(d)")
                }
                self.configureMenuRow(cell, String(localized: "Reconcile reminder"),
                                      value: label, options: options) { [weak self] raw in
                    self?.write(ReconcileReminder.key, Int(raw) ?? ReconcileReminder.defaultDays)
                }

            case Self.hapticsID:
                self.configureToggleRow(cell, String(localized: "Haptic feedback"),
                                        isOn: self.hapticsEnabled) { [weak self] on in
                    self?.write(Haptics.enabledKey, on)
                }

            case Self.adjustID:
                self.configureToggleRow(cell, String(localized: "Adjust Balance in Add sheet"),
                                        isOn: self.showAdjustInAddSheet) { [weak self] on in
                    self?.write(Key.showAdjust, on)
                }

            case Self.fabID:
                self.configureToggleRow(cell, String(localized: "Floating add button"),
                                        isOn: self.fabEnabled) { [weak self] on in
                    self?.write(Key.fabEnabled, on)
                }

            case Self.fabPositionID:
                cell.contentConfiguration = UIHostingConfiguration {
                    Picker("", selection: Binding(
                        get: { self.fabPositionRaw },
                        set: { self.write(Key.fabPosition, $0) })) {
                        ForEach(FabPosition.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

            default:
                break
            }
        }

        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            switch self.sectionIDs[indexPath.section] {
            case .theme: cfg.text = String(localized: "Theme")
            case .textSize: cfg.text = String(localized: "Text size")
            case .language: cfg.text = String(localized: "Language")
            case .activityFeed: cfg.text = String(localized: "Activity feed")
            case .accounts: cfg.text = String(localized: "Accounts")
            case .quickAdd: cfg.text = String(localized: "Quick add button")
            case .haptics, .addSheet: cfg.text = nil
            }
            view.contentConfiguration = cfg
        }

        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] view, _, indexPath in
            guard let self, self.sectionIDs.indices.contains(indexPath.section) else { return }
            var cfg = view.defaultContentConfiguration()
            switch self.sectionIDs[indexPath.section] {
            case .textSize:
                cfg.text = self.useSystemTextSize
                    ? String(localized: "Follows the system Text Size setting.")
                    : String(localized: "Overrides the system text size inside finch.")
            case .language:
                // Turns orange once the language changed, to nudge the relaunch.
                cfg.text = self.showRelaunchNote
                    ? String(localized: "Relaunch finch to apply the new language.")
                    : String(localized: "Switches the app's language. Takes effect after relaunch.")
                cfg.textProperties.color = self.showRelaunchNote ? .systemOrange : .secondaryLabel
            case .activityFeed:
                cfg.text = String(localized: "Group by month also applies to an account's transaction list.")
            case .accounts:
                cfg.text = String(localized: "Reconciled accounts show an orange badge once the last reconcile is older than this. Off keeps them green forever.")
            case .haptics:
                cfg.text = String(localized: "A gentle tap on saves, errors, and deletes. Also respects your device's System Haptics setting.")
            case .addSheet:
                cfg.text = String(localized: "Adds an Adjust Balance type to the Add-transaction sheet. It's always available from an account's \u{22EF} menu.")
            case .quickAdd:
                cfg.text = String(localized: "The floating + for quickly adding a transaction on iPhone. The toolbar and \u{2318}N ways to add are always available.")
            case .theme:
                cfg.text = nil
            }
            view.contentConfiguration = cfg
        }

        dataSource = UICollectionViewDiffableDataSource<SectionID, String>(collectionView: collectionView) {
            cv, indexPath, id in cv.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        dataSource.supplementaryViewProvider = { cv, kind, indexPath in
            kind == UICollectionView.elementKindSectionFooter
                ? cv.dequeueConfiguredReusableSupplementary(using: footer, for: indexPath)
                : cv.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    /// Label plus a `UISwitch` accessory. The switch owns its touches; the row is not
    /// selectable, matching a SwiftUI `Toggle` row.
    /// SwiftUI draws the switch — see `HostedToggleRows` for why UIKit cannot.
    private func configureToggleRow(_ cell: UICollectionViewListCell, _ label: String,
                                    isOn: Bool, onChange: @escaping (Bool) -> Void) {
        cell.accessories = []
        cell.contentConfiguration = UIHostingConfiguration {
            HostedToggleRow(title: label, isOn: isOn, onChange: onChange)
        }
    }

    /// A pull-down menu button showing the current value — what SwiftUI's default
    /// `Picker` renders as inside a form. The SwiftUI screen chose that style
    /// deliberately: an inline wheel dwarfed the page for a six-item choice.
    private func configureMenuRow(_ cell: UICollectionViewListCell, _ label: String, value: String,
                                  options: [(String, String)], onPick: @escaping (String) -> Void) {
        var cfg = cell.defaultContentConfiguration()
        cfg.text = label
        cell.contentConfiguration = cfg

        let button = UIButton(type: .system)
        button.setTitle(value, for: .normal)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: options.map { title, raw in
            UIAction(title: title, state: title == value ? .on : .off) { _ in onPick(raw) }
        })
        cell.accessories = [.customView(configuration: .init(customView: button, placement: .trailing()))]
    }

    // MARK: Writes
    //
    // Every one of these is a UserDefaults write, exactly as @AppStorage did. The
    // snapshot is reapplied afterwards because rows and footers here are derived from
    // the preference — the slider and the FAB position row appear and disappear, and
    // two footers change wording.

    private func write(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        applySnapshot()
    }

    private func setLanguage(_ raw: String) {
        defaults.set(raw, forKey: Key.language)
        let lang = AppLanguage(rawValue: raw) ?? .system
        if lang == .system { defaults.removeObject(forKey: "AppleLanguages") }
        else { defaults.set([lang.rawValue], forKey: "AppleLanguages") }
        showRelaunchNote = true
        applySnapshot()
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<SectionID, String>()

        snap.appendSections([.theme])
        snap.appendItems([Self.appearancePickerID], toSection: .theme)

        snap.appendSections([.textSize])
        var sizeItems = [Self.systemSizeID]
        if !useSystemTextSize { sizeItems += [Self.sliderID, Self.sampleID] }
        snap.appendItems(sizeItems, toSection: .textSize)

        snap.appendSections([.language])
        snap.appendItems([Self.languageID], toSection: .language)

        snap.appendSections([.activityFeed])
        snap.appendItems([Self.groupByMonthID, Self.relativeDatesID], toSection: .activityFeed)

        snap.appendSections([.accounts])
        snap.appendItems([Self.reconcileID], toSection: .accounts)

        snap.appendSections([.haptics])
        snap.appendItems([Self.hapticsID], toSection: .haptics)

        snap.appendSections([.addSheet])
        snap.appendItems([Self.adjustID], toSection: .addSheet)

        snap.appendSections([.quickAdd])
        var fabItems = [Self.fabID]
        if fabEnabled { fabItems.append(Self.fabPositionID) }
        snap.appendItems(fabItems, toSection: .quickAdd)

        // Every row reads a preference under a fixed identifier, so without this a
        // write would leave the control showing its previous value.
        let carried = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(snap.itemIdentifiers.filter(carried.contains))

        sectionIDs = snap.sectionIdentifiers
        dataSource.apply(snap, animatingDifferences: false)
        // Footers derive from the same preferences and are NOT reconfigured by a
        // snapshot apply, so they need refreshing explicitly.
        refreshVisibleFooters()
    }

    /// Diffable will not re-render a supplementary view whose section identifier is
    /// unchanged — the same trap the month headers hit on the account detail. Two of
    /// these footers change wording (and one changes colour) with the preferences
    /// above them.
    private func refreshVisibleFooters() {
        let kind = UICollectionView.elementKindSectionFooter
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            guard let view = collectionView.supplementaryView(forElementKind: kind, at: indexPath)
                    as? UICollectionViewListCell,
                  sectionIDs.indices.contains(indexPath.section) else { continue }
            var cfg = view.defaultContentConfiguration()
            switch sectionIDs[indexPath.section] {
            case .textSize:
                cfg.text = useSystemTextSize
                    ? String(localized: "Follows the system Text Size setting.")
                    : String(localized: "Overrides the system text size inside finch.")
            case .language:
                cfg.text = showRelaunchNote
                    ? String(localized: "Relaunch finch to apply the new language.")
                    : String(localized: "Switches the app's language. Takes effect after relaunch.")
                cfg.textProperties.color = showRelaunchNote ? .systemOrange : .secondaryLabel
            default:
                continue   // the static footers need no refresh
            }
            view.contentConfiguration = cfg
        }
    }
}

extension AppearanceSettingsVC: UICollectionViewDelegate {
    /// Nothing on this screen is a tappable ROW: every control owns its own touches
    /// (switches, sliders, segmented pickers, pull-down menus).
    func collectionView(_ cv: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }
}
#endif
