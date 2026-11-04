//
//  GameBoardViewModel+Unveil.swift
//  Treachery-iOS
//

import Foundation

extension GameBoardViewModel {

    /// Where the signed-in player's unveil is, from their confirmation to
    /// the end of the reveal; `unveilCurrentPlayer()` moves it along. The
    /// reveal plays only once the server has unveiled them: a failed call
    /// goes straight back to `idle`, with an error.
    enum UnveilProgress: Equatable {
        /// Nothing under way.
        case idle
        /// The unveilPlayer call is under way.
        case sending
        /// The call succeeded. The identity header turns edge-on…
        case flippingAway
        /// …then back face-up, under the "IDENTITY REVEALED" banner.
        case revealing

        /// How long the header takes to turn edge-on.
        static let flipDuration: Duration = .milliseconds(300)
        /// How long the banner stays up once the header has turned back.
        static let bannerDuration: Duration = .seconds(2)
    }
}
