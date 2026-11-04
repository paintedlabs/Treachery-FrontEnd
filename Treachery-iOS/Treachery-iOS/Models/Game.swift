//
//  Game.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

/// Where a game is in its lifecycle, as stored in `state`.
///
/// `unknown` keeps a state this build doesn't recognise (one a newer server or
/// web client added) instead of failing to decode the whole game, which the
/// listeners used to report as a deleted game. Screens show "needs a newer
/// version" for it rather than guessing what it means.
enum GameState: Hashable {
    case waiting
    case inProgress
    case finished
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "waiting": self = .waiting
        case "in_progress": self = .inProgress
        case "finished": self = .finished
        default: self = .unknown(rawValue)
        }
    }

    /// The string the server stores, unchanged for an unknown state.
    var rawValue: String {
        switch self {
        case .waiting: return "waiting"
        case .inProgress: return "in_progress"
        case .finished: return "finished"
        case .unknown(let rawValue): return rawValue
        }
    }

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

extension GameState: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Game: Codable, Identifiable, Hashable {
    var id: String
    let code: String
    let hostId: String
    var state: GameState
    let maxPlayers: Int
    let startingLife: Int
    var winningTeam: String?
    var gameMode: GameMode
    var playerIds: [String]
    let createdAt: Date
    var lastActivityAt: Date?
    var planechase: PlanechaseState?
    var winnerUserIds: [String]
    var maxTraitorRarity: Rarity?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case hostId = "host_id"
        case state
        case gameMode = "game_mode"
        case maxPlayers = "max_players"
        case startingLife = "starting_life"
        case winningTeam = "winning_team"
        case playerIds = "player_ids"
        case createdAt = "created_at"
        case lastActivityAt = "last_activity_at"
        case planechase
        case winnerUserIds = "winner_user_ids"
        case maxTraitorRarity = "max_traitor_rarity"
    }

    // Custom decoder: defaults playerIds to [] for documents created before
    // this field existed, preventing decoding crashes on legacy data.
    // An unrecognised state or game_mode string decodes as `.unknown` rather
    // than throwing (see GameState and GameMode).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        code = try container.decode(String.self, forKey: .code)
        hostId = try container.decode(String.self, forKey: .hostId)
        state = try container.decode(GameState.self, forKey: .state)
        maxPlayers = try container.decode(Int.self, forKey: .maxPlayers)
        startingLife = try container.decode(Int.self, forKey: .startingLife)
        gameMode = try container.decodeIfPresent(GameMode.self, forKey: .gameMode) ?? .treachery
        winningTeam = try container.decodeIfPresent(String.self, forKey: .winningTeam)
        playerIds = try container.decodeIfPresent([String].self, forKey: .playerIds) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        planechase = try container.decodeIfPresent(PlanechaseState.self, forKey: .planechase)
        winnerUserIds = try container.decodeIfPresent([String].self, forKey: .winnerUserIds) ?? []
        // try? so an unrecognised rarity string degrades to nil instead of
        // dropping the whole game document (same treatment as Player.role).
        maxTraitorRarity = try? container.decodeIfPresent(Rarity.self, forKey: .maxTraitorRarity)
    }

    init(
        id: String,
        code: String,
        hostId: String,
        state: GameState,
        gameMode: GameMode = .treachery,
        maxPlayers: Int,
        startingLife: Int,
        winningTeam: String?,
        playerIds: [String],
        createdAt: Date,
        lastActivityAt: Date? = nil,
        planechase: PlanechaseState? = nil,
        winnerUserIds: [String] = [],
        maxTraitorRarity: Rarity? = nil
    ) {
        self.id = id
        self.code = code
        self.hostId = hostId
        self.state = state
        self.gameMode = gameMode
        self.maxPlayers = maxPlayers
        self.startingLife = startingLife
        self.winningTeam = winningTeam
        self.playerIds = playerIds
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.planechase = planechase
        self.winnerUserIds = winnerUserIds
        self.maxTraitorRarity = maxTraitorRarity
    }
}

// MARK: - Starting Life

extension Game {
    /// The starting life totals the create screen's stepper and the lobby's
    /// menu offer: 20 to 60 in steps of 5. createGame and updateGameSettings
    /// (functions/src/callables/lobby.js) must accept every one of them, so
    /// the functions that do have to be deployed before a build offering
    /// them ships.
    static let startingLifeRange = 20...60
    static let startingLifeStep = 5
    static let startingLifeOptions = Array(
        stride(from: startingLifeRange.lowerBound, through: startingLifeRange.upperBound, by: startingLifeStep)
    )
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
