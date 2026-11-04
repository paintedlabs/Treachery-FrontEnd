import Testing
import Foundation
@testable import Treachery_iOS

/// What the board shows while life changes are on their way to the server.
/// LifeLedger is a pure value, so these drive it directly;
/// OptimisticLifeTrackingTests covers the view model's timing and calls.
struct LifeLedgerTests {

    // MARK: - Helpers

    /// A snapshot: player i is "p<i>" with the i-th life total.
    private func server(_ lifeTotals: Int...) -> [Player] {
        lifeTotals.enumerated().map { i, life in
            Player(
                id: "p\(i)", orderId: i, userId: "u\(i)", displayName: "Player \(i)",
                role: .guardian, identityCardId: nil, lifeTotal: life,
                isEliminated: false, isUnveiled: false, joinedAt: Date(timeIntervalSince1970: 0)
            )
        }
    }

    private func shown(_ ledger: LifeLedger, on server: [Player], for playerId: String = "p0") -> Int? {
        ledger.displayedPlayers(from: server).first { $0.id == playerId }?.lifeTotal
    }

    /// Begins a batch, failing the test if none begins.
    private func beginBatch(
        in ledger: inout LifeLedger,
        for playerId: String = "p0",
        serverLife: Int = 40
    ) throws -> LifeLedger.Batch {
        let batch = ledger.beginBatch(for: playerId, serverLife: serverLife)
        return try #require(batch)
    }

    // MARK: - Pending and in flight

    @Test func pendingTapsShowOnTopOfTheServerTotal() {
        var ledger = LifeLedger()
        ledger.record(-1, for: "p0")
        ledger.record(-1, for: "p0")

        #expect(shown(ledger, on: server(40, 40)) == 38)
        #expect(shown(ledger, on: server(40, 40), for: "p1") == 40)
        #expect(ledger.playersWithPendingTaps == ["p0"])
    }

    @Test func aBatchTakesThePendingTapsAndStaysOnScreen() throws {
        var ledger = LifeLedger()
        ledger.record(-1, for: "p0")
        ledger.record(-2, for: "p0")

        let batch = try beginBatch(in: &ledger)

        #expect(batch.amount == -3)
        #expect(ledger.playersWithPendingTaps.isEmpty)
        #expect(shown(ledger, on: server(40)) == 37)
    }

    @Test func noBatchWithoutPendingTaps() {
        var ledger = LifeLedger()
        let fromNothing = ledger.beginBatch(for: "p0", serverLife: 40)
        #expect(fromNothing == nil)

        ledger.record(1, for: "p0")
        ledger.record(-1, for: "p0")
        let fromTapsThatCancelOut = ledger.beginBatch(for: "p0", serverLife: 40)
        #expect(fromTapsThatCancelOut == nil)
    }

    @Test func aTapWhileABatchIsInFlightShowsBoth() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        _ = try beginBatch(in: &ledger)

        ledger.record(-1, for: "p0")

        #expect(shown(ledger, on: server(40)) == 36)
    }

    @Test func neverShowsLessThanZero() {
        var ledger = LifeLedger()
        ledger.record(-5, for: "p0")
        #expect(shown(ledger, on: server(2)) == 0)
    }

    // MARK: - Snapshots

    @Test func anotherPlayersChangeLeavesTheBatchOnScreen() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        _ = try beginBatch(in: &ledger)

        let snapshot = server(40, 35)
        ledger.reconcile(with: snapshot)

        #expect(shown(ledger, on: snapshot) == 37)
    }

    @Test func theEchoTakesTheBatchOffTheOverlay() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        _ = try beginBatch(in: &ledger)
        ledger.record(-1, for: "p0")

        let echo = server(37)
        ledger.reconcile(with: echo)

        // 37 from the server, plus the tap that hasn't been sent; not 33.
        #expect(shown(ledger, on: echo) == 36)
    }

    // MARK: - Responses

    @Test func aResponseBeforeTheEchoKeepsTheChangeOnScreen() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let batch = try beginBatch(in: &ledger)

        ledger.recordSuccess(of: batch, newLife: 37)
        #expect(shown(ledger, on: server(40)) == 37)

        let echo = server(37)
        ledger.reconcile(with: echo)
        #expect(shown(ledger, on: echo) == 37)
    }

    @Test(arguments: [37, nil] as [Int?])
    func aResponseAfterTheEchoSettlesTheBatch(newLife: Int?) throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let batch = try beginBatch(in: &ledger)
        let echo = server(37)
        ledger.reconcile(with: echo)

        ledger.recordSuccess(of: batch, newLife: newLife)
        ledger.record(-1, for: "p0")

        #expect(shown(ledger, on: echo) == 36)
        let next = try beginBatch(in: &ledger, serverLife: 37)
        #expect(next.amount == -1)
    }

    @Test func aResponseTheSnapshotAlreadyShowsSettlesTheBatch() throws {
        // Another device's +3 and this -3 land together: the snapshot never
        // moves off 40, so only the response can settle the batch.
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let batch = try beginBatch(in: &ledger)
        let snapshot = server(40)
        ledger.reconcile(with: snapshot)
        #expect(shown(ledger, on: snapshot) == 37)

        ledger.recordSuccess(of: batch, newLife: 40)

        #expect(shown(ledger, on: snapshot) == 40)
    }

    @Test func aFailureDropsTheBatchButKeepsLaterTaps() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let batch = try beginBatch(in: &ledger)
        ledger.record(-1, for: "p0")

        let outcome = ledger.recordFailure(of: batch)

        #expect(outcome == .reverted)
        #expect(shown(ledger, on: server(40)) == 39)
        // The later tap goes out on its own; the failed -3 never does.
        let next = try beginBatch(in: &ledger)
        #expect(next.amount == -1)
    }

    @Test func aFailureAfterTheEchoKeepsTheServerTotal() throws {
        // The server applied the -3 and the snapshot showed it, but the
        // response was lost.
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let batch = try beginBatch(in: &ledger)
        let echo = server(37)
        ledger.reconcile(with: echo)

        let outcome = ledger.recordFailure(of: batch)

        #expect(outcome == .unconfirmed)
        #expect(shown(ledger, on: echo) == 37)
    }

    // MARK: - One batch at a time

    @Test func theNextBatchWaitsUntilThePreviousSettles() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let first = try beginBatch(in: &ledger)
        ledger.record(-1, for: "p0")
        let whileSent = ledger.beginBatch(for: "p0", serverLife: 40)
        #expect(whileSent == nil)

        // The echo alone isn't enough: the call is still out.
        ledger.reconcile(with: server(37))
        let whileCallIsOut = ledger.beginBatch(for: "p0", serverLife: 37)
        #expect(whileCallIsOut == nil)

        ledger.recordSuccess(of: first, newLife: 37)
        let next = try beginBatch(in: &ledger, serverLife: 37)
        #expect(next.amount == -1)
    }

    @Test func aLateOutcomeLeavesTheNextBatchAlone() throws {
        // Same player, same amount: only the batch itself tells them apart.
        var ledger = LifeLedger()
        ledger.record(-1, for: "p0")
        let first = try beginBatch(in: &ledger)
        ledger.reconcile(with: server(39))
        ledger.recordSuccess(of: first, newLife: 39)
        ledger.record(-1, for: "p0")
        let second = try beginBatch(in: &ledger, serverLife: 39)
        #expect(second != first)

        let outcome = ledger.recordFailure(of: first)

        #expect(outcome == nil)
        #expect(shown(ledger, on: server(39)) == 38)
    }

    @Test func playersStayIndependent() throws {
        var ledger = LifeLedger()
        ledger.record(-2, for: "p0")
        ledger.record(3, for: "p1")
        _ = try beginBatch(in: &ledger)
        let p1Batch = try beginBatch(in: &ledger, for: "p1")

        // p0's echo doesn't settle p1's batch, and p1's failure leaves p0 alone.
        let echo = server(38, 40)
        ledger.reconcile(with: echo)
        #expect(shown(ledger, on: echo, for: "p0") == 38)
        #expect(shown(ledger, on: echo, for: "p1") == 43)

        ledger.recordFailure(of: p1Batch)
        #expect(shown(ledger, on: echo, for: "p0") == 38)
        #expect(shown(ledger, on: echo, for: "p1") == 40)
    }

    // MARK: - Echo timeout

    @Test func anEchoTimeoutSettlesAConfirmedBatchNoSnapshotShowed() throws {
        // This -3 lands, then another device's +3, and the only snapshot
        // shows both: still 40, the baseline.
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let batch = try beginBatch(in: &ledger)
        ledger.recordSuccess(of: batch, newLife: 37)
        let snapshot = server(40)
        ledger.reconcile(with: snapshot)
        #expect(ledger.isWaitingForEcho(for: "p0"))
        #expect(shown(ledger, on: snapshot) == 37)
        ledger.record(-1, for: "p0")
        let whileWaiting = ledger.beginBatch(for: "p0", serverLife: 40)
        #expect(whileWaiting == nil)

        ledger.recordEchoTimeout(of: batch)

        #expect(!ledger.isWaitingForEcho(for: "p0"))
        #expect(shown(ledger, on: snapshot) == 39)
        let next = try beginBatch(in: &ledger)
        #expect(next.amount == -1)
    }

    @Test func anEchoTimeoutOnlySettlesTheBatchItWasFor() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        let first = try beginBatch(in: &ledger)
        // Its call is still out: not confirmed, so nothing to time out.
        #expect(!ledger.isWaitingForEcho(for: "p0"))
        ledger.recordEchoTimeout(of: first)
        #expect(shown(ledger, on: server(40)) == 37)

        ledger.recordSuccess(of: first, newLife: 37)
        ledger.reconcile(with: server(37))
        ledger.record(-1, for: "p0")
        let second = try beginBatch(in: &ledger, serverLife: 37)
        ledger.recordSuccess(of: second, newLife: 36)
        #expect(ledger.isWaitingForEcho(for: "p0"))

        // A timeout left over from the first doesn't touch the second.
        ledger.recordEchoTimeout(of: first)
        #expect(ledger.isWaitingForEcho(for: "p0"))
        #expect(shown(ledger, on: server(37)) == 36)
    }

    // MARK: - Leaving

    @Test func takingPendingTapsLeavesBatchesInFlight() throws {
        var ledger = LifeLedger()
        ledger.record(-3, for: "p0")
        _ = try beginBatch(in: &ledger)
        ledger.record(-1, for: "p0")
        ledger.record(2, for: "p1")

        let taken = ledger.takePendingTaps()

        #expect(taken == ["p0": -1, "p1": 2])
        #expect(ledger.playersWithPendingTaps.isEmpty)
        #expect(shown(ledger, on: server(40, 40)) == 37)
        #expect(shown(ledger, on: server(40, 40), for: "p1") == 40)
    }
}
