import XCTest
import Combine
import FinchCore
@testable import FinchApp

/// A write makes the store emit once per reprojected slice. A screen should rebuild
/// once per write, not once per slice.
@MainActor
final class StoreChangeCoalescingTests: XCTestCase {

    func test_aBurstIsDeliveredOnceAfterItLands() {
        let subject = PassthroughSubject<Void, Never>()
        var state = 0
        var seen: [Int] = []
        let c = subject.coalescedOnMain().sink { seen.append(state) }
        defer { c.cancel() }

        for i in 1...17 { state = i; subject.send() }
        XCTAssertEqual(seen, [], "never synchronously, mid-burst")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(seen, [17], "once, and after the last change")

        state = 18; subject.send()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(seen, [17, 18], "the next write is its own burst")
    }

    /// The real store: one write emits many times, and arrives as one.
    func test_oneWriteToTheStoreArrivesOnce() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let account = try XCTUnwrap(store.accounts.first)
        var raw = 0, coalesced = 0
        let a = store.objectWillChange.sink { raw += 1 }
        let b = store.objectWillChange.coalescedOnMain().sink { coalesced += 1 }
        defer { a.cancel(); b.cancel() }

        try store.apply(.addTransaction, Args([
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(account.id),
            "amount": .double(-12), "merchant": .string("Bakery"),
            "date": .string(store.wallToday), "skipRules": .bool(true)]))
        try await Task.sleep(for: .milliseconds(200))   // lets the main queue run
        XCTAssertGreaterThan(raw, 1, "the store emits once per slice")
        XCTAssertEqual(coalesced, 1)
    }
}
