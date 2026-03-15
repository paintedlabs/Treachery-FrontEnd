//
//  Role.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import SwiftUI

enum Role: String, Codable, CaseIterable, Identifiable {
    case leader
    case guardian
    case assassin
    case traitor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leader:   return "Leader"
        case .guardian:  return "Guardian"
        case .assassin:  return "Assassin"
        case .traitor:   return "Traitor"
        }
    }

    var color: Color {
        switch self {
        case .leader:   return .mtgLeader
        case .guardian:  return .mtgGuardian
        case .assassin:  return .mtgAssassin
        case .traitor:   return .mtgTraitor
        }
    }

    var winConditionText: String {
        switch self {
        case .leader:
            return "Eliminate all Assassins and Traitors to win."
        case .guardian:
            return "Keep the Leader alive. Eliminate all Assassins and Traitors."
        case .assassin:
            return "Eliminate the Leader while at least one Assassin survives."
        case .traitor:
            return "Be the last player standing."
        }
    }

    /// Role distribution for a given player count.
    /// Returns (leaders, guardians, assassins, traitors).
    static func distribution(forPlayerCount count: Int) -> (leaders: Int, guardians: Int, assassins: Int, traitors: Int) {
        switch count {
        #if DEBUG
        case 1:  return (1, 0, 0, 0)   // Solo: leader only (test card/UI flow)
        case 2:  return (1, 0, 1, 0)   // Leader vs assassin
        case 3:  return (1, 0, 1, 1)   // Leader, assassin, traitor
        #endif
        case 4:  return (1, 0, 2, 1)
        case 5:  return (1, 1, 2, 1)
        case 6:  return (1, 1, 3, 1)
        case 7:  return (1, 2, 3, 1)
        case 8:  return (1, 2, 3, 2)
        default: return (1, 0, 2, 1)
        }
    }

    /// Minimum number of players required to start a game.
    static var minimumPlayerCount: Int {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "devModeEnabled") ? 1 : 4
        #else
        return 4
        #endif
    }
}
