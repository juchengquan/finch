import SwiftUI

/// How many columns the hosting NavigationSplitView has — the persisted Bool
/// maps to different visibility values per arity.
enum SplitColumns { case two, three }

/// Pure mapping between the persisted "sidebar collapsed" Bool and
/// `NavigationSplitViewVisibility` (unit-tested — the only real logic here).
enum SplitVisibilityMapping {
    static func visibility(collapsed: Bool, columns: SplitColumns) -> NavigationSplitViewVisibility {
        switch columns {
        case .three: return collapsed ? .doubleColumn : .all
        case .two:   return collapsed ? .detailOnly : .doubleColumn
        }
    }

    /// `String(describing: .automatic)` — used to discriminate the transient
    /// `.automatic` from `.detailOnly`: `.automatic` is internally
    /// `(kind: .detailOnly, isAutomatic: true)` and the type's opaque `==`
    /// compares only `kind`, so `.automatic == .detailOnly` is TRUE on current
    /// SDKs. The description differs (`isAutomatic:`), making it the only
    /// reliable discriminator.
    private static let automaticDescription = String(describing: NavigationSplitViewVisibility.automatic)

    /// The Bool a visibility value represents, or nil for transient/other values
    /// (`.automatic`, or arity-mismatched states like `.detailOnly` on a
    /// three-column shell) — nil means "don't record".
    static func collapsed(from v: NavigationSplitViewVisibility, columns: SplitColumns) -> Bool? {
        if String(describing: v) == automaticDescription { return nil }
        if v == visibility(collapsed: true, columns: columns) { return true }
        if v == visibility(collapsed: false, columns: columns) { return false }
        return nil
    }
}

/// Owns the `columnVisibility` state for a NavigationSplitView: seeds it from the
/// persisted per-device pref, records only *trustworthy* changes, and re-asserts
/// the pref after rotation. The #414-deferred trap this solves: iPadOS
/// auto-collapses columns on rotation to portrait, so naïvely persisting every
/// change would record that auto-collapse as a user preference and pin the
/// sidebar closed. Rules:
///   • persist a change only while the container is landscape (width > height);
///   • on portrait → landscape, re-apply the stored pref (undo the auto-collapse);
///   • portrait/overlay toggles are deliberately not recorded (accepted
///     limitation — see the spec).
/// macOS windows are effectively always landscape, so Mac toggles persist
/// naturally through the same path.
struct PersistedSplitVisibility<Content: View>: View {
    static var storageKey: String { "finch.sidebarCollapsed" }

    let columns: SplitColumns
    @ViewBuilder var content: (Binding<NavigationSplitViewVisibility>) -> Content

    @AppStorage(PersistedSplitVisibility.storageKey) private var sidebarCollapsed = false
    @State private var visibility: NavigationSplitViewVisibility
    /// Pessimistic default: nothing is recorded until geometry PROVES landscape.
    /// Starting `true` would open a cold-launch-in-portrait race where the
    /// system's auto-collapse gets recorded before the GeometryReader corrects
    /// the flag — the exact #414 trap this type exists to prevent. (Also note:
    /// a macOS window dragged taller than wide counts as portrait here, so
    /// toggles made in a tall window intentionally don't persist.)
    @State private var isLandscape = false

    /// Seeds `visibility` at construction time rather than in `.onAppear`.
    /// `NavigationSplitView` reads `columnVisibility` at first layout, before
    /// `.onAppear` fires — for the 3-column/`.balanced` shell specifically,
    /// a value assigned in `.onAppear` arrives one runloop tick too late and
    /// the split view has already committed to its default (`.all`) layout,
    /// so `.doubleColumn` never visually takes. Setting the initial `@State`
    /// value here (via `_visibility = State(initialValue:)`) makes the
    /// collapsed value available for that very first layout pass.
    /// `@AppStorage`/`UserDefaults.standard` can't be read through the
    /// property-wrapper (`sidebarCollapsed`) this early, so this reads
    /// `UserDefaults.standard` directly with the same key.
    init(columns: SplitColumns, @ViewBuilder content: @escaping (Binding<NavigationSplitViewVisibility>) -> Content) {
        self.columns = columns
        self.content = content
        let collapsed = UserDefaults.standard.bool(forKey: Self.storageKey)
        _visibility = State(initialValue: SplitVisibilityMapping.visibility(collapsed: collapsed, columns: columns))
    }

    var body: some View {
        content($visibility)
            .onAppear {
                // Harmless re-assert: `visibility` is already seeded correctly
                // by `init`. Kept so a change to `sidebarCollapsed` made
                // between `init` and `.onAppear` (e.g. by another split view
                // sharing the same key) is still picked up.
                visibility = SplitVisibilityMapping.visibility(collapsed: sidebarCollapsed, columns: columns)
            }
            .onChange(of: visibility) { _, v in
                guard isLandscape,
                      let collapsed = SplitVisibilityMapping.collapsed(from: v, columns: columns),
                      collapsed != sidebarCollapsed else { return }
                sidebarCollapsed = collapsed
            }
            // Read the container size WITHOUT wrapping the split view (a wrapping
            // GeometryReader can disturb NavigationSplitView's layout).
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { isLandscape = geo.size.width > geo.size.height }
                        .onChange(of: geo.size) { _, size in
                            let landscape = size.width > size.height
                            guard landscape != isLandscape else { return }
                            isLandscape = landscape
                            if landscape {   // portrait → landscape: undo any auto-collapse
                                visibility = SplitVisibilityMapping.visibility(collapsed: sidebarCollapsed, columns: columns)
                            }
                        }
                }
            )
    }
}
