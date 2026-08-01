import XCTest
@testable import FinchApp
import FinchCore

/// The work a write kicks off that **no pixel is waiting for** — the widget and
/// Watch snapshot, the Spotlight index, scheduled notifications, the DB-info probe,
/// the auto-backup timer — must not run between the tap and the next frame.
///
/// It used to. Confirming a pending transaction ran, inline on the main actor:
/// a whole-ledger reprojection, then `WidgetSnapshotWriter.write` (a pass over every
/// transaction per budget, a JSON encode and a synchronous App Group file write),
/// then `makeDBInfo` (COUNT(*) across every table — which the LAUNCH path already
/// refuses to do on the main actor, for exactly this reason). All of it landed in
/// the window the row-move animation needed, which is what "the animation is not
/// fluent" turned out to mean.
///
/// These tests pin the split. `ambientRunCount` is the seam: every claim below is a
/// statement about when that number changes.
@MainActor
final class AmbientSideEffectsTests: XCTestCase {

    private func loadedStore() async throws -> FinchStore {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: url))
        return store
    }

    private func aPendingTransaction(_ store: FinchStore) throws -> String {
        try store.apply(.addTransaction, Args([
            "ledgerId": .string(store.activeLedgerId),
            "accountId": .string(try XCTUnwrap(store.accounts.first).id),
            "amount": .double(-12), "merchant": .string("Ambient"),
            "date": .string(store.wallToday), "status": .string("pending")]))
        return try XCTUnwrap(store.txns.first { $0.merchant == "Ambient" }).id
    }

    /// Sleep past the debounce with margin, then let the queued work run.
    private func waitPastDebounce() async {
        try? await Task.sleep(for: FinchStore.ambientDebounce + .milliseconds(300))
    }

    // MARK: not in the animation's window

    /// The claim that matters: the write returns without having done the ambient
    /// work. If this fails, the row is animating against a busy main thread again.
    func test_aWriteDoesNotRunTheAmbientRoundInline() async throws {
        let store = try await loadedStore()
        await waitPastDebounce()          // let the load's own round settle
        let before = store.ambientRunCount

        _ = try aPendingTransaction(store)

        XCTAssertEqual(store.ambientRunCount, before,
                       "the ambient round ran inline with the write — back in the animation's window")
    }

    /// Deferred, not dropped.
    func test_theAmbientRoundRunsAfterTheDebounce() async throws {
        let store = try await loadedStore()
        await waitPastDebounce()
        let before = store.ambientRunCount

        _ = try aPendingTransaction(store)
        await waitPastDebounce()

        XCTAssertEqual(store.ambientRunCount, before + 1,
                       "the widget / Spotlight / DB-info round never fired")
    }

    /// The reason for a debounce rather than a plain hop off the current turn: a
    /// burst must cost ONE round, not one per write. A multi-select confirm, an
    /// import and a sync replay are all bursts.
    func test_aBurstOfWritesCollapsesIntoOneRound() async throws {
        let store = try await loadedStore()
        await waitPastDebounce()
        let before = store.ambientRunCount

        for i in 0..<10 {
            try store.apply(.addTransaction, Args([
                "ledgerId": .string(store.activeLedgerId),
                "accountId": .string(try XCTUnwrap(store.accounts.first).id),
                "amount": .double(-1), "merchant": .string("Burst \(i)"),
                "date": .string(store.wallToday)]))
        }
        await waitPastDebounce()

        XCTAssertEqual(store.ambientRunCount, before + 1,
                       "ten writes fired \(store.ambientRunCount - before) rounds; the debounce is not coalescing")
    }

    // MARK: the projection is NOT deferred

    /// Only the invisible work moved. The projected state a row-move animates
    /// between must still be published by the time the write returns, or the row
    /// would sit still for 400ms and then jump — a worse bug than the one being
    /// fixed.
    func test_theProjectionStillLandsSynchronously() async throws {
        let store = try await loadedStore()
        let id = try aPendingTransaction(store)

        XCTAssertEqual(store.txns.first { $0.id == id }?.pending, true)
        try store.apply(.confirmTransaction, Args(["id": .string(id)]))
        XCTAssertEqual(store.txns.first { $0.id == id }?.pending, false,
                       "the confirm is not visible until the debounce fires — the row cannot animate")
    }

    // MARK: backgrounding

    /// A stale widget is never more visible than on the home screen the user just
    /// went back to, so backgrounding forces the pending round rather than leaving
    /// it queued until the next write.
    func test_flushRunsThePendingRoundImmediately() async throws {
        let store = try await loadedStore()
        await waitPastDebounce()
        let before = store.ambientRunCount

        _ = try aPendingTransaction(store)
        store.flushAmbientSideEffects()
        // No debounce wait — a short yield is all a flush should need.
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(store.ambientRunCount, before + 1, "flush did not run the pending round")
    }

    /// And a flush with nothing pending is a no-op, so backgrounding an idle app
    /// does not rebuild the widget for no reason.
    func test_flushWithNothingPendingDoesNothing() async throws {
        let store = try await loadedStore()
        await waitPastDebounce()
        let before = store.ambientRunCount

        store.flushAmbientSideEffects()
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(store.ambientRunCount, before, "an idle flush ran a round anyway")
    }

    // MARK: multi-select is one write

    /// Confirming a selection used to loop `apply`, so ten rows meant ten full
    /// rounds of post-write work while ten rows tried to animate. One batch, one
    /// round.
    func test_bulkConfirmIsASingleWrite() async throws {
        let store = try await loadedStore()
        let account = try XCTUnwrap(store.accounts.first).id
        var ids: [String] = []
        for i in 0..<5 {
            try store.apply(.addTransaction, Args([
                "ledgerId": .string(store.activeLedgerId), "accountId": .string(account),
                "amount": .double(-3), "merchant": .string("Bulk \(i)"),
                "date": .string(store.wallToday), "status": .string("pending")]))
            ids.append(try XCTUnwrap(store.txns.first { $0.merchant == "Bulk \(i)" }).id)
        }
        await waitPastDebounce()
        let before = store.ambientRunCount

        XCTAssertEqual(store.confirmTransactions(ids), 5)
        for id in ids {
            XCTAssertEqual(store.txns.first { $0.id == id }?.pending, false, "row \(id) still pending")
        }

        await waitPastDebounce()
        XCTAssertEqual(store.ambientRunCount, before + 1,
                       "five confirms fired \(store.ambientRunCount - before) rounds, not one")
    }

    /// An id that resolves to nothing does not sink the batch.
    ///
    /// Note what the engine actually does: `confirmTransaction` returns silently
    /// when `resolveEntryRef` finds no row, so a missing id is a no-op that does not
    /// throw — the same as it was under the old per-row loop. The returned count is
    /// therefore "ops that did not throw", NOT "rows changed", and this test says so
    /// rather than pretending the count catches a stale selection.
    func test_bulkConfirm_anUnresolvableIdDoesNotSinkTheBatch() async throws {
        let store = try await loadedStore()
        let id = try aPendingTransaction(store)

        let applied = store.confirmTransactions([id, "no-such-transaction"])
        XCTAssertEqual(applied, 2, "the engine treats a missing row as a silent no-op, not a rejection")
        XCTAssertEqual(store.txns.first { $0.id == id }?.pending, false,
                       "the real row must still confirm alongside the dud")
    }
}
