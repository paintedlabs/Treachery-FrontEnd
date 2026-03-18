//
//  Deck.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/18/26.
//

import Foundation
import SwiftUI

enum ManaColor: String, Codable, CaseIterable, Hashable {
    case white = "W"
    case blue = "U"
    case black = "B"
    case red = "R"
    case green = "G"
    case colorless = "C"

    var displayName: String {
        switch self {
        case .white: return "White"
        case .blue: return "Blue"
        case .black: return "Black"
        case .red: return "Red"
        case .green: return "Green"
        case .colorless: return "Colorless"
        }
    }

    var color: Color {
        switch self {
        case .white: return Color(red: 0.96, green: 0.94, blue: 0.86)
        case .blue: return Color(red: 0.30, green: 0.55, blue: 0.79)
        case .black: return Color(red: 0.55, green: 0.47, blue: 0.58)
        case .red: return Color(red: 0.79, green: 0.30, blue: 0.30)
        case .green: return Color(red: 0.24, green: 0.66, blue: 0.36)
        case .colorless: return Color(red: 0.65, green: 0.65, blue: 0.65)
        }
    }
}

struct Deck: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    var name: String
    var commanderName: String
    var partnerCommanderName: String?
    var colorIdentity: [ManaColor]
    let createdAt: Date
    var lastPlayedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case commanderName = "commander_name"
        case partnerCommanderName = "partner_commander_name"
        case colorIdentity = "color_identity"
        case createdAt = "created_at"
        case lastPlayedAt = "last_played_at"
    }

    var commanderDisplayName: String {
        if let partner = partnerCommanderName, !partner.isEmpty {
            return "\(commanderName) & \(partner)"
        }
        return commanderName
    }
}
