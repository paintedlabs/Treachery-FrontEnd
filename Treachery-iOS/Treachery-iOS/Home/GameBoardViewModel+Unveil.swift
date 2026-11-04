//
//  GameBoardViewModel+Unveil.swift
//  Treachery-iOS
//

import Foundation

extension GameBoardViewModel {

    /// Where the signed-in player's unveil is, from their confirmation to
    /// the players snapshot that shows it; `unveilCurrentPlayer()` moves it
    /// along. The reveal plays only once the server has unveiled them: its
    /// reply says so, or a snapshot does when the reply was lost after the
    /// server had committed.
    enum UnveilProgress: Equatable {
        /// Nothing under way.
        case idle
        /// The unveilPlayer call is under way.
        case sending
        /// The server has unveiled them. The identity header turns edge-on…
        case flippingAway
        /// …then back face-up, under the "IDENTITY REVEALED" banner.
        case revealing
        /// The reveal is over, but no players snapshot shows the unveil
        /// yet. Unveil stays off until one does: the server would refuse
        /// another ("Already unveiled.").
        case awaitingSnapshot
        /// The call failed, and no snapshot shows the unveil. The message
        /// stays until the player tries again, or until a snapshot shows
        /// the unveil went through after all: a lost reply isn't a lost
        /// unveil.
        case failed(message: String)

        /// How long the header takes to turn edge-on.
        static let flipDuration: Duration = .milliseconds(300)
        /// How long the banner stays up once the header has turned back.
        static let bannerDuration: Duration = .seconds(2)
    }

    /// Whether the board offers Unveil: to a Treachery player still in the
    /// game whose identity is hidden, and not to a Leader, who is always
    /// face-up (the server refuses them). It goes once the server has
    /// unveiled them, though a snapshot may show that only later.
    var offersUnveil: Bool {
        guard isTreacheryActive, seat == .playing, let player = currentPlayer,
              !player.isUnveiled, player.role != .leader else { return false }
        switch unveilProgress {
        case .idle, .sending, .failed:
            return true
        case .flippingAway, .revealing, .awaitingSnapshot:
            return false
        }
    }

    /// Why the last unveil failed, while that's still the latest word on it.
    var unveilFailure: String? {
        guard case .failed(let message) = unveilProgress else { return nil }
        return message
    }
}
