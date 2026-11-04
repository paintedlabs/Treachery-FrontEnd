//
//  GameMode.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import Foundation

/// Which rules a game is played with, as stored in `game_mode`.
///
/// `unknown` keeps a mode this build doesn't recognise (one a newer server or
/// web client added) instead of failing to decode the whole game. It includes
/// neither Treachery nor Planechase. A waiting lobby still opens with it, but
/// the host can't start it from this build (see `LobbyViewModel.canStartGame`)
/// and the board asks for a newer version rather than guessing at its rules
/// (see `GameBoardViewModel.status`).
enum GameMode: Hashable {
    case treachery
    case planechase
    case treacheryPlanechase
    case none
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "treachery": self = .treachery
        case "planechase": self = .planechase
        case "treachery_planechase": self = .treacheryPlanechase
        case "none": self = .none
        default: self = .unknown(rawValue)
        }
    }

    /// The string the server stores, unchanged for an unknown mode.
    var rawValue: String {
        switch self {
        case .treachery: return "treachery"
        case .planechase: return "planechase"
        case .treacheryPlanechase: return "treachery_planechase"
        case .none: return "none"
        case .unknown(let rawValue): return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .treachery: return "Treachery"
        case .planechase: return "Planechase"
        case .treacheryPlanechase: return "Both"
        case .none: return "Life Tracker"
        case .unknown: return "Unsupported Mode"
        }
    }

    var includesTreachery: Bool {
        self == .treachery || self == .treacheryPlanechase
    }

    var includesPlanechase: Bool {
        self == .planechase || self == .treacheryPlanechase
    }

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

extension GameMode: CaseIterable {
    /// The modes this build can create and play. `unknown` is left out: it
    /// only ever arrives from the server.
    static let allCases: [GameMode] = [.treachery, .planechase, .treacheryPlanechase, .none]
}

extension GameMode: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
