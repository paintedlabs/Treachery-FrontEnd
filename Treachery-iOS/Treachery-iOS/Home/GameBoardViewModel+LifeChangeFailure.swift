//
//  GameBoardViewModel+LifeChangeFailure.swift
//  Treachery-iOS
//

import Foundation

extension GameBoardViewModel {

    /// A life change whose call failed, and what the board says about it.
    struct LifeChangeFailure: Equatable {
        /// What the board knows about the change.
        enum Kind: Equatable {
            /// No snapshot had shown the change when its call failed, so the
            /// board went back to the server's total. Most likely the change
            /// never reached the server, but a reply lost on its way back
            /// looks the same; see `revised(by:)`.
            case notApplied(baseline: Int, amount: Int)
            /// The board may show the change already, so making it again
            /// could apply it twice.
            case unconfirmed
            /// The server turned the change down, for this reason, so it
            /// certainly wasn't applied.
            case refused(reason: String)
        }

        let playerId: String
        let playerName: String
        let kind: Kind

        /// What the board says, naming the player.
        var message: String {
            switch kind {
            case .notApplied:
                return "Couldn't update \(playerName)'s life. Check your connection and try again."
            case .unconfirmed:
                return "Couldn't confirm \(playerName)'s life change. Check the total before changing it again."
            case .refused(let reason):
                return "Couldn't update \(playerName)'s life. \(reason)"
            }
        }

        /// This failure once a later snapshot shows the player's total. A
        /// change that wasn't applied as far as the board knew may have
        /// landed after all. A total that moved off the baseline by exactly
        /// the change means it did, and there's nothing left to explain
        /// (nil). Any other move can't be told apart from someone else's
        /// change, so the board can't confirm it, and "try again" could
        /// apply it twice.
        func revised(by player: Player) -> Self? {
            guard case .notApplied(let baseline, let amount) = kind,
                  player.lifeTotal != baseline else { return self }
            // The server stops at 0, as the board does.
            if player.lifeTotal == max(0, baseline + amount) { return nil }
            return Self(playerId: playerId, playerName: playerName, kind: .unconfirmed)
        }
    }
}
