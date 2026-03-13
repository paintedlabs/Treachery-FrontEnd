//
//  Rarity.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

enum Rarity: String, Codable, CaseIterable, Identifiable {
    case uncommon
    case rare
    case mythic
    case special

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uncommon: return "Uncommon"
        case .rare:     return "Rare"
        case .mythic:   return "Mythic"
        case .special:  return "Special"
        }
    }
}
