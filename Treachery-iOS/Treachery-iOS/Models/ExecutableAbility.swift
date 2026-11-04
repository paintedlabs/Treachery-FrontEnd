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

    /// The ability `player`'s card gives them. The server's resolvers check
    /// the card they were dealt as well as the one they hold (abilities.js):
    /// one of these cards that reached them through a Puppet Master swap
    /// gives them nothing, so it's nil then.
    init?(heldBy player: Player) {
        guard let cardId = player.identityCardId,
              player.originalIdentityCardId == nil || player.originalIdentityCardId == cardId
        else { return nil }
        self.init(cardId: cardId)
    }

    var displayName: String {
        switch self {
        case .metamorph: return "The Metamorph"
        case .puppetMaster: return "The Puppet Master"
        case .wearerOfMasks: return "The Wearer of Masks"
        }
    }
}
