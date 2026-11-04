//
//  GameBoardViewModel+Accessibility.swift
//  Treachery-iOS
//

import SwiftUI

extension GameBoardViewModel {

    /// VoiceOver's swipe up or down on a player's life total: the same
    /// 1-point change as their + and − buttons, through the same checks and
    /// debounce.
    func adjustLife(for playerId: String, _ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            adjustLife(for: playerId, by: 1)
        case .decrement:
            adjustLife(for: playerId, by: -1)
        @unknown default:
            break
        }
    }
}

// MARK: - Announcements
//
// What VoiceOver reads out as the board changes; the board posts it. Nothing
// once the game is over: Game Over covers the board by then, and the board's
// news would be read out over the results.

extension GameBoardViewModel {

    /// Whether VoiceOver hears about the board's changes: only while the
    /// game goes on.
    var announcesBoardChanges: Bool {
        !isGameFinished
    }

    /// What to read out when `errorMessage` becomes `message`: the error
    /// itself. It appears in the controls pinned below the players, away
    /// from where the player is looking or VoiceOver is reading.
    func announcement(forError message: String?) -> String? {
        announcesBoardChanges ? message : nil
    }

    /// What to read out when the failed life changes go from `old` to
    /// `new`; see `LifeChangeFailure.announcements(from:to:)`. A failed
    /// change can put a total back with no other sign, and the banner is
    /// away from the rows.
    func announcements(forFailuresFrom old: [LifeChangeFailure], to new: [LifeChangeFailure]) -> [LifeChangeFailure.Announcement] {
        announcesBoardChanges ? LifeChangeFailure.announcements(from: old, to: new) : []
    }

    /// What to read out when the signed-in user's seat goes from `old` to
    /// `new`. Elimination changes the board with no other sign: the life
    /// buttons stop working, and the spectator bar, now the way home,
    /// appears at the bottom.
    func announcement(forSeatChangeFrom old: Seat, to new: Seat) -> String? {
        guard announcesBoardChanges, old == .playing, new == .spectating else { return nil }
        return "You've been eliminated. You can keep watching, or use Leave Game at the bottom of the screen."
    }

    /// What to read out when the unveil moves on to `progress`. The banner
    /// is the only sign the unveil went through, and the error, away below
    /// the players, the only sign it didn't: the button just goes back to
    /// Unveil.
    func announcement(for progress: UnveilProgress) -> String? {
        guard announcesBoardChanges else { return nil }
        switch progress {
        case .revealing:
            return "Identity revealed"
        case .failed(let message):
            return message
        case .idle, .sending, .flippingAway, .awaitingSnapshot:
            return nil
        }
    }
}
