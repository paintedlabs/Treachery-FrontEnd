//
//  Game.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

enum GameState: String, Codable {
    case waiting
    case inProgress = "in_progress"
    case finished
}

struct Game: Codable, Identifiable {
    let id: String
    let code: String
    let hostId: String
    var state: GameState
    let maxPlayers: Int
    let startingLife: Int
    var winningTeam: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case hostId = "host_id"
        case state
        case maxPlayers = "max_players"
        case startingLife = "starting_life"
        case winningTeam = "winning_team"
        case createdAt = "created_at"
    }
}
