//
//  PlaneDatabase.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import Foundation

final class PlaneDatabase {
    static let shared = PlaneDatabase()

    private var cards: [PlaneCard] = []

    private init() {
        loadCards()
    }

    private func loadCards() {
        guard let url = Bundle.main.url(forResource: "PlaneCards", withExtension: "json") else {
            assertionFailure("PlaneCards.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            cards = try decoder.decode([PlaneCard].self, from: data)
        } catch {
            assertionFailure("Failed to decode PlaneCards.json: \(error)")
        }
    }

    // MARK: - Queries

    /// All cards including phenomena.
    var allCards: [PlaneCard] { cards }

    /// All planes, excluding phenomena.
    var allPlanes: [PlaneCard] {
        cards.filter { !$0.isPhenomenon }
    }

    func plane(withId id: String) -> PlaneCard? {
        cards.first { $0.id == id }
    }

    func randomPlane(excluding usedIds: Set<String>) -> PlaneCard? {
        let available = allPlanes.filter { !usedIds.contains($0.id) }
        return available.randomElement()
    }
}
