//
//  GameBoardViewModel+Status.swift
//  Treachery-iOS
//

import Foundation

extension GameBoardViewModel {

    /// What the board and Game Over can show, given what the listeners have
    /// reported. The data itself lives in `game` and `players`.
    enum Status: Equatable {
        /// Waiting for the game and its players.
        case loading
        /// The game and its players are here to show.
        case ready
        /// The game's state or mode is one this build doesn't know, or its
        /// data can't be read. Playing it here could show the wrong controls
        /// or hide the right ones.
        case needsNewerVersion
        /// The server confirmed the game no longer exists.
        case unavailable
        /// The server refused to show the user this game's players: they're
        /// no longer in it. Nothing here can change that.
        case notInGame
        /// A listener failed; `retry()` re-attaches.
        case failed
    }
}
