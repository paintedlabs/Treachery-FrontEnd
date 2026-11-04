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
/// an echo can't be taken for a later batch's.
///
/// A pure value: GameBoardViewModel feeds it taps, snapshots and call
/// outcomes, and owns the timing and the calls.
struct LifeLedger {

    /// One player's taps, sent together as one adjustLife call.
    struct Batch: Equatable {
        let playerId: String
        let amount: Int
        /// Tells this batch from the player's earlier and later ones.
        fileprivate let number: Int
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
    /// - Parameter serverLife: The player's life in the latest snapshot. The
    ///   batch shows until a snapshot moves off it.
    mutating func beginBatch(for playerId: String, serverLife: Int) -> Batch? {
        guard var entry = entries[playerId], entry.pending != 0, entry.inFlight == nil else { return nil }
        batchCount += 1
        let batch = Batch(playerId: playerId, amount: entry.pending, number: batchCount)
        entry.pending = 0
        entry.inFlight = InFlight(batch: batch, baseline: serverLife, progress: .sent)
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
            inFlight.progress = .confirmed
            entries[batch.playerId]?.inFlight = inFlight
        case .confirmed:
            break
        }
    }

    /// The call for `batch` failed. Its amount is dropped, so the board falls
    /// back to the server's total. It isn't queued again: adjustLife adds
    /// whatever it's given, and a call that failed after the server applied
    /// it (the response lost on the way back) would be applied twice.
    mutating func recordFailure(of batch: Batch) {
        guard inFlight(of: batch) != nil else { return }
        settle(batch)
    }

    // MARK: - Snapshots

    /// Applies a players snapshot. A batch whose player's life has moved off
    /// its baseline is taken to be in the server's total: the server applied
    /// it, or another device changed that life and the server's total is the
    /// one to show.
    mutating func reconcile(with serverPlayers: [Player]) {
        for player in serverPlayers {
            guard var inFlight = entries[player.id]?.inFlight,
                  player.lifeTotal != inFlight.baseline else { continue }
            switch inFlight.progress {
            case .sent:
                inFlight.progress = .reflected
                entries[player.id]?.inFlight = inFlight
            case .confirmed:
                settle(inFlight.batch)
            case .reflected:
                break
            }
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
        /// The player's server life when the batch was sent.
        let baseline: Int
        var progress: Progress

        /// Nothing once a snapshot has taken the batch in.
        var shownAmount: Int {
            progress == .reflected ? 0 : batch.amount
        }
    }

    /// How far a batch has got. It settles, and leaves the ledger, once its
    /// call has returned and either failed or the server's total includes it.
    private enum Progress {
        /// Neither the response nor a snapshot that includes it has arrived.
        /// Shown.
        case sent
        /// A snapshot moved off the baseline, but the call hasn't returned.
        /// Not shown: the server's total includes it.
        case reflected
        /// The call succeeded, but no snapshot has moved off the baseline yet.
        /// Shown until one does.
        case confirmed
    }

    private func inFlight(of batch: Batch) -> InFlight? {
        guard let inFlight = entries[batch.playerId]?.inFlight, inFlight.batch == batch else { return nil }
        return inFlight
    }

    private mutating func settle(_ batch: Batch) {
        entries[batch.playerId]?.inFlight = nil
    }
}
