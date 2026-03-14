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

struct Game: Codable, Identifiable, Hashable {
    let id: String
    let code: String
    let hostId: String
    var state: GameState
    let maxPlayers: Int
    let startingLife: Int
    var winningTeam: String?
    var playerIds: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case hostId = "host_id"
        case state
        case maxPlayers = "max_players"
        case startingLife = "starting_life"
        case winningTeam = "winning_team"
        case playerIds = "player_ids"
        case createdAt = "created_at"
    }

    // Custom decoder: defaults playerIds to [] for documents created before
    // this field existed, preventing decoding crashes on legacy data.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        hostId = try container.decode(String.self, forKey: .hostId)
        state = try container.decode(GameState.self, forKey: .state)
        maxPlayers = try container.decode(Int.self, forKey: .maxPlayers)
        startingLife = try container.decode(Int.self, forKey: .startingLife)
        winningTeam = try container.decodeIfPresent(String.self, forKey: .winningTeam)
        playerIds = try container.decodeIfPresent([String].self, forKey: .playerIds) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    init(
        id: String,
        code: String,
        hostId: String,
        state: GameState,
        maxPlayers: Int,
        startingLife: Int,
        winningTeam: String?,
        playerIds: [String],
        createdAt: Date
    ) {
        self.id = id
        self.code = code
        self.hostId = hostId
        self.state = state
        self.maxPlayers = maxPlayers
        self.startingLife = startingLife
        self.winningTeam = winningTeam
        self.playerIds = playerIds
        self.createdAt = createdAt
    }
}

// MARK: - Game Errors

enum GameError: LocalizedError {
    case codeGenerationFailed
    case gameFull
    case gameNotFound
    case gameAlreadyStarted
    case cardAssignmentFailed

    var errorDescription: String? {
        switch self {
        case .codeGenerationFailed: return "Could not generate a unique game code. Please try again."
        case .gameFull: return "This game is full."
        case .gameNotFound: return "No game found with that code."
        case .gameAlreadyStarted: return "This game has already started."
        case .cardAssignmentFailed: return "Could not assign identity cards. Please try again."
        }
    }
}
