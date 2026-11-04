//
//  FirestoreManaging+Players.swift
//  Treachery-iOS
//

import Foundation
import os

private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Profile")

extension FirestoreManaging {
    /// The players of each of `games` by game id, read in parallel. A game
    /// whose players fail to load is left out, so a caller can tell players
    /// it doesn't know from a game with none: Profile counts that game's
    /// result as unknown, and History shows it without players.
    func playersByGame(for games: [Game]) async -> [String: [Player]] {
        await withTaskGroup(of: (gameId: String, players: [Player]?).self) { group in
            for game in games {
                group.addTask {
                    do {
                        return (game.id, try await self.getPlayers(gameId: game.id))
                    } catch {
                        logger.error("Loading the players of a finished game failed: \(String(describing: error), privacy: .private)")
                        return (game.id, nil)
                    }
                }
            }

            var playersByGame: [String: [Player]] = [:]
            for await result in group {
                if let players = result.players {
                    playersByGame[result.gameId] = players
                }
            }
            return playersByGame
        }
    }
}
