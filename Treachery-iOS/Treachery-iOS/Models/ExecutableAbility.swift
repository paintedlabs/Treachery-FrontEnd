//
//  ExecutableAbility.swift
//  Treachery-iOS
//

import Foundation

enum ExecutableAbility: String, CaseIterable {
    case metamorph = "traitor_07"
    case puppetMaster = "traitor_09"
    case wearerOfMasks = "traitor_13"

    init?(cardId: String) {
        self.init(rawValue: cardId)
    }

    var displayName: String {
        switch self {
        case .metamorph: return "The Metamorph"
        case .puppetMaster: return "The Puppet Master"
        case .wearerOfMasks: return "The Wearer of Masks"
        }
    }
}
