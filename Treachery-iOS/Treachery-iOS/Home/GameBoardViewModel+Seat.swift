//
//  GameBoardViewModel+Seat.swift
//  Treachery-iOS
//

import Foundation

// MARK: - Seat
//
// What the signed-in user can see and do on the board. What they can do
// follows from their seat, not from the game's mode: the server eliminates
// players in every mode, so a player who is out spectates in every mode.

extension GameBoardViewModel {

    /// How the signed-in user takes part in the game, whatever its mode.
    enum Seat: Equatable {
        /// The players snapshot doesn't include them.
        case unseated
        /// In the game and still alive.
        case playing
        /// Eliminated, at 0 life or by forfeiting. They can watch the rest
        /// of the game, and leave whenever they like.
        case spectating
    }

    /// What the spectator bar's Leave button does.
    enum SpectatorLeave: Equatable {
        /// Goes home. The game carries on without them.
        case goHome
        /// Asks first. They're the host of a game only the host can end, and
        /// it would carry on with nobody able to end it.
        case confirmFirst
    }

    var seat: Seat {
        guard let currentPlayer else { return .unseated }
        return currentPlayer.isEliminated ? .spectating : .playing
    }

    /// Only players still in the game change life totals. The server would
    /// take a spectator's change, but web doesn't offer one either: they're
    /// out of the game.
    var canAdjustLife: Bool { seat == .playing }

    /// Only players still in the game roll the planar die; rollPlanarDie
    /// refuses anyone else.
    var canRollDie: Bool { seat == .playing }

    /// The host ends any game without Treachery's win conditions, eliminated
    /// or not: nothing else ends it.
    var canEndGame: Bool { isHost && !isTreacheryActive }

    /// The spectator bar's Leave, or nil when there's no spectator bar.
    /// Every eliminated player gets one, in every game mode: the board hides
    /// the back button and the tab bar, and they have no other way home.
    var spectatorLeave: SpectatorLeave? {
        guard seat == .spectating else { return nil }
        return canEndGame ? .confirmFirst : .goHome
    }

    func canSeeRole(of player: Player) -> Bool {
        // Only Treachery deals roles. Elsewhere there's none to show, even
        // for players the server marks unveiled when they're eliminated.
        guard isTreacheryActive else { return false }
        // You can always see your own role
        if player.userId == currentUserId { return true }
        // Leaders are always face-up (visible to everyone)
        if player.role == .leader { return true }
        // Unveiled but face-down cards are hidden (Puppet Master / Metamorph swap)
        if player.isUnveiled && !player.isFaceDown { return true }
        // Puppet Master can peek at all face-down cards
        if let myCardId = currentPlayer?.identityCardId,
           myCardId == ExecutableAbility.puppetMaster.rawValue,
           currentPlayer?.isUnveiled == true {
            return true
        }
        return false
    }
}
