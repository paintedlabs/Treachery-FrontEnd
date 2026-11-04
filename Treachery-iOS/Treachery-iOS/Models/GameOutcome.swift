//
//  GameOutcome.swift
//  Treachery-iOS
//

import Foundation

/// How a finished game ended for one player.
enum GameOutcome: Equatable {
    /// The player was on the winning side.
    case won
    /// Someone else won.
    case lost
    /// The game ended without a winner, for example because the host ended
    /// it early.
    case noWinner
    /// The game has a winner, but not one this player can be scored
    /// against: their role is unknown (their seat didn't load, say), or the
    /// winning team is one this build doesn't recognize.
    case unknown
}

extension Game {
    /// How this game ended for the player `userId`.
    ///
    /// The one win rule behind Profile's stats and Game History. It matches
    /// the rule onGameFinished (functions/src/triggers.js) awards ELO by:
    /// - Treachery modes compare `winning_team` with the player's role, and
    ///   the Guardians share the Leader's win. The role is the player's
    ///   current one, not the dealt one, because a Puppet Master swap moves a
    ///   player to the team they finish on.
    /// - Other modes have no teams. The host's pick, `winner_user_ids`,
    ///   decides, and every other player in the game lost.
    ///
    /// - Parameters:
    ///   - userId: A player in this game.
    ///   - role: That player's role here, or nil when it's unknown (for
    ///     example, their seat didn't load). Only Treachery modes need it.
    func outcome(forUserId userId: String, role: Role?) -> GameOutcome {
        if gameMode.includesTreachery {
            guard let winningTeam else { return .noWinner }
            guard let winningRole = Role(rawValue: winningTeam), let role else { return .unknown }
            let isOnWinningTeam = winningRole == .leader
                ? role == .leader || role == .guardian
                : role == winningRole
            return isOnWinningTeam ? .won : .lost
        }
        guard !winnerUserIds.isEmpty else { return .noWinner }
        return winnerUserIds.contains(userId) ? .won : .lost
    }
}
