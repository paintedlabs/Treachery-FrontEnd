//
//  CardDatabase.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

final class CardDatabase {
    static let shared = CardDatabase()

    private var cards: [IdentityCard] = []

    private init() {
        loadCards()
    }

    private func loadCards() {
        guard let url = Bundle.main.url(forResource: "IdentityCards", withExtension: "json") else {
            assertionFailure("IdentityCards.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            cards = try decoder.decode([IdentityCard].self, from: data)
        } catch {
            assertionFailure("Failed to decode IdentityCards.json: \(error)")
        }
    }

    // MARK: - Queries

    var allCards: [IdentityCard] { cards }

    func card(withId id: String) -> IdentityCard? {
        cards.first { $0.id == id }
    }

    func cards(forRole role: Role) -> [IdentityCard] {
        cards.filter { $0.role == role }
    }

    func cards(forRarity rarity: Rarity) -> [IdentityCard] {
        cards.filter { $0.rarity == rarity }
    }

    func randomCards(forRole role: Role, count: Int) -> [IdentityCard] {
        Array(cards(forRole: role).shuffled().prefix(count))
    }
}
