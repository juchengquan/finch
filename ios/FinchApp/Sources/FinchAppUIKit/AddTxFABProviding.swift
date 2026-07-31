#if os(iOS)
import UIKit
import Combine

/// How a pushed screen tells the shell's floating add-`+` about itself.
///
/// The SwiftUI FAB learns the same two things from preferences published up the
/// view tree — `AddTxContextKey` for the page subject, `SelectionActiveKey` for
/// multi-select. Preferences do not cross into UIKit, so a converted screen
/// states them directly.
///
/// Conformance is OPTIONAL: `AddTxFABHost` casts the top view controller to this
/// and falls back to the same empty defaults when it does not conform. A screen
/// converted later therefore gets a working FAB without implementing anything,
/// and only opts in when it has a subject to seed or a reason to hide.
@MainActor
protocol AddTxFABProviding: UIViewController {
    /// Seeds the Add sheet, exactly as this screen's own toolbar `+` does.
    var addTxContext: AddTxContext { get }
    /// True while the FAB must stay out of the way — multi-select's bulk-action bar.
    var hidesAddTxFAB: Bool { get }
    /// Fires when either of the above changes, so the host can re-evaluate.
    var addTxFABStateDidChange: AnyPublisher<Void, Never> { get }
}

extension AddTxFABProviding {
    var addTxContext: AddTxContext { AddTxContext() }
    var hidesAddTxFAB: Bool { false }
    var addTxFABStateDidChange: AnyPublisher<Void, Never> {
        Empty<Void, Never>().eraseToAnyPublisher()
    }
}
#endif
