import Combine
import Foundation

extension Publisher where Failure == Never {

    /// One delivery per burst, on main, after the burst has landed.
    ///
    /// `reprojectActiveLedger` assigns ~17 `@Published` slices back to back, so one
    /// write makes the store emit ~17 times in a few milliseconds. A screen that
    /// rebuilt on each `objectWillChange` rebuilt ~17 times per write. The emissions
    /// all arrive within one main-queue turn, so waiting out that turn and keeping
    /// only the last collapses them into one rebuild, which then sees every slice's
    /// new value. `AccountsListVC.setNeedsSnapshot` does the same by hand.
    func coalescedOnMain() -> AnyPublisher<Void, Never> {
        map { _ in () }
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
