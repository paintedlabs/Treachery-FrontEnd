//
//  LifeLedger.swift
//  Treachery-iOS
//

import Foundation

/// The life changes this device has made that the server hasn't confirmed
/// yet, laid over the server's totals so a tap shows at once.
///
/// Each player has two amounts: taps still waiting out the debounce
/// (pending), and the batch sent as one adjustLife call (in flight). The
/// board shows server life + pending + in flight.
///
/// The in-flight amount stays on screen until a players snapshot moves that
/// player's life off its baseline, the value it had when the batch was sent.
/// That is the web client's rule (useGameBoard.ts). Dropping the amount as
/// the call went out, as this app used to, showed the old total again
/// whenever a snapshot or a tap redrew the board before the server's echo.
///
/// A player's next batch waits until the previous one has settled: its call
/// has returned, and it either failed or the server's total includes it. So
/// only one batch per player is ever in flight, its calls never overlap, and
/// an echo can't be taken for a later batch's. A batch whose echo never comes
/// is settled by `recordEchoTimeout(of:)`, so it can't hold the next one back
/// for good, though only once snapshots are arriving again.
///
/// A pure value: GameBoardViewModel feeds it taps, snapshots and call
/// outcomes, and owns the timing and the calls.
struct LifeLedger {

    /// One player's taps, sent together as one adjustLife call.
    struct Batch: Equatable {
        let playerId: String
        let amount: Int
        /// The player's life in the latest snapshot when the batch was sent.
        /// The batch shows until a snapshot moves off it.
        let baseline: Int
        /// Tells this batch from the player's earlier and later ones.
        fileprivate let number: Int
    }

    /// What the board shows after a batch's call fails.
    enum FailureOutcome: Equatable {
        /// The batch is off the board, which shows the server's total again.
        case reverted
        /// A snapshot had already moved the player's life off the baseline,
        /// so the board was showing the server's total without the batch on
        /// top, and still does. Usually the server applied the batch and
        /// only its response failed, but the move may have been another
        /// device's change, or the late echo of an earlier batch.
        case unconfirmed
    }

    /// What happens when a confirmed batch's wait for its echo runs out.
    enum EchoTimeout: Equatable {
        /// The batch settled. The board shows the latest snapshot's total.
        case settled
        /// No players snapshot has come since the batch's response, so the
        /// listener may just be behind, and the total it last showed comes
        /// from before the change. The batch stays on screen; wait again.
        case waitAgain
        /// The batch isn't waiting for its echo any more.
        case notWaiting
    }

    private var entries: [String: Entry] = [:]
    private var batchCount = 0

    // MARK: - Taps

    /// Adds a tap to the player's pending amount.
    mutating func record(_ amount: Int, for playerId: String) {
        entries[playerId, default: Entry()].pending += amount
    }

    /// Players with taps that haven't been sent.
    var playersWithPendingTaps: [String] {
        entries.filter { $0.value.pending != 0 }.map(\.key)
    }

    // MARK: - Sending

    /// Puts the player's pending taps in flight as one batch. Returns nil when
    /// there are none, or while their previous batch hasn't settled.
    ///
    /// - Parameter serverLife: The player's life in the latest snapshot, the
    ///   batch's baseline.
    mutating func beginBatch(for playerId: String, serverLife: Int) -> Batch? {
        guard var entry = entries[playerId], entry.pending != 0, entry.inFlight == nil else { return nil }
        batchCount += 1
        let batch = Batch(playerId: playerId, amount: entry.pending, baseline: serverLife, number: batchCount)
        entry.pending = 0
        entry.inFlight = InFlight(batch: batch, progress: .sent)
        entries[playerId] = entry
        return batch
    }

    /// Removes every player's pending taps and returns them, for sending
    /// outside the ledger when the board goes away.
    mutating func takePendingTaps() -> [String: Int] {
        var taken: [String: Int] = [:]
        for playerId in playersWithPendingTaps {
            taken[playerId] = entries[playerId]?.pending
            entries[playerId]?.pending = 0
        }
        return taken
    }

    // MARK: - Outcomes

    /// The call for `batch` succeeded.
    ///
    /// - Parameter newLife: The total the server stored, if the response
    ///   says.
    mutating func recordSuccess(of batch: Batch, newLife: Int?) {
        guard var inFlight = inFlight(of: batch) else { return }
        switch inFlight.progress {
        case .reflected:
            settle(batch)
        case .sent where newLife == inFlight.baseline:
            // The server's total after this batch equals the baseline, which
            // is what the latest snapshot shows (one that moved off it would
            // have made this `.reflected`). Another device's change cancelled
            // this one out, so no snapshot would ever settle it.
            settle(batch)
        case .sent:
            // The echo hasn't arrived; keep showing the change until it does.
            inFlight.progress = .confirmed(snapshotSinceResponse: false)
            entries[batch.playerId]?.inFlight = inFlight
        case .confirmed:
            break
        }
    }

    /// Whether the player's batch has succeeded but no snapshot has shown it
    /// yet. It stays on screen, and holds back the player's next batch, until
    /// one does or `recordEchoTimeout(of:)` settles it.
    func isWaitingForEcho(for playerId: String) -> Bool {
        if case .confirmed = entries[playerId]?.inFlight?.progress { return true }
        return false
    }

    /// No snapshot has shown `batch` long after its call succeeded. The
    /// batch settles, and the board shows the latest snapshot's total, once
    /// a players snapshot (for anyone) has come since the response.
    ///
    /// Snapshots can stay at the baseline for good after the server applied
    /// the batch: another device's change can take the total straight back,
    /// and this device may only get the snapshot with both. Without a limit,
    /// the batch would stay on screen, and hold back the player's next one,
    /// until someone changed that player's life again. But with no snapshot
    /// since the response, the listener may just be behind (reconnecting,
    /// say): settling then would put back a total from before a change the
    /// server confirmed, with nothing to say so, and making the change again
    /// would apply it twice.
    @discardableResult
    mutating func recordEchoTimeout(of batch: Batch) -> EchoTimeout {
        guard case .confirmed(let snapshotSinceResponse) = inFlight(of: batch)?.progress else { return .notWaiting }
        guard snapshotSinceResponse else { return .waitAgain }
        settle(batch)
        return .settled
    }

    /// The call for `batch` failed. Its amount is dropped, so the board falls
    /// back to the server's total. It isn't queued again: adjustLife adds
    /// whatever it's given, and a call that failed after the server applied
    /// it (the response lost on the way back) would be applied twice.
    ///
    /// - Returns: What the board shows now, or nil if `batch` had already
    ///   settled and nothing changed.
    @discardableResult
    mutating func recordFailure(of batch: Batch) -> FailureOutcome? {
        guard let inFlight = inFlight(of: batch) else { return nil }
        settle(batch)
        return inFlight.progress == .reflected ? .unconfirmed : .reverted
    }

    // MARK: - Snapshots

    /// Applies a players snapshot. A batch whose player's life has moved off
    /// its baseline is taken to be in the server's total: the server applied
    /// it, or another device changed that life and the server's total is the
    /// one to show.
    ///
    /// A player the snapshot shows eliminated loses the taps not sent yet,
    /// held ones included: the server refuses any change to them.
    ///
    /// Any snapshot also shows the listener is delivering, which lets a
    /// confirmed batch's echo wait end; see `recordEchoTimeout(of:)`.
    mutating func reconcile(with serverPlayers: [Player]) {
        for player in serverPlayers where player.isEliminated {
            entries[player.id]?.pending = 0
        }
        for (playerId, entry) in entries {
            guard var inFlight = entry.inFlight else { continue }
            let serverLife = serverPlayers.first { $0.id == playerId }?.lifeTotal
            let moved = serverLife != nil && serverLife != inFlight.baseline
            switch inFlight.progress {
            case .sent where moved:
                inFlight.progress = .reflected
            case .confirmed where moved:
                settle(inFlight.batch)
                continue
            case .confirmed:
                inFlight.progress = .confirmed(snapshotSinceResponse: true)
            case .sent, .reflected:
                continue
            }
            entries[playerId]?.inFlight = inFlight
        }
    }

    // MARK: - Display

    /// The players as the board shows them: the server's totals plus this
    /// device's unconfirmed changes, never below 0 (the server stops there
    /// too).
    func displayedPlayers(from serverPlayers: [Player]) -> [Player] {
        serverPlayers.map { player in
            guard let entry = entries[player.id], entry.shownChange != 0 else { return player }
            var shown = player
            shown.lifeTotal = max(0, player.lifeTotal + entry.shownChange)
            return shown
        }
    }

    // MARK: - Private

    private struct Entry {
        /// Taps not sent yet.
        var pending = 0
        /// The batch sent and not settled yet.
        var inFlight: InFlight?

        /// What this player's total shows on top of the server's.
        var shownChange: Int {
            pending + (inFlight?.shownAmount ?? 0)
        }
    }

    private struct InFlight {
        let batch: Batch
        var progress: Progress

        var baseline: Int { batch.baseline }

        /// Nothing once a snapshot has taken the batch in.
        var shownAmount: Int {
            progress == .reflected ? 0 : batch.amount
        }
    }

    /// How far a batch has got. It settles, and leaves the ledger, once its
    /// call has returned and either failed or the server's total includes it.
    private enum Progress: Equatable {
        /// Neither the response nor a snapshot that includes it has arrived.
        /// Shown.
        case sent
        /// A snapshot moved off the baseline, but the call hasn't returned.
        /// Not shown: the server's total includes it.
        case reflected
        /// The call succeeded, but no snapshot has moved off the baseline yet.
        /// Shown until one does, or until the echo times out, which needs a
        /// players snapshot to have come since the response.
        case confirmed(snapshotSinceResponse: Bool)
    }

    private func inFlight(of batch: Batch) -> InFlight? {
        guard let inFlight = entries[batch.playerId]?.inFlight, inFlight.batch == batch else { return nil }
        return inFlight
    }

    private mutating func settle(_ batch: Batch) {
        entries[batch.playerId]?.inFlight = nil
    }
}
