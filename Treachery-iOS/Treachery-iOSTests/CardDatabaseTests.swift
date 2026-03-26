import Testing
@testable import Treachery_iOS

struct CardDatabaseTests {

    // MARK: - Loading

    @Test func loadsCards() {
        let db = CardDatabase.shared
        #expect(!db.allCards.isEmpty)
    }

    @Test func has62Cards() {
        #expect(CardDatabase.shared.allCards.count == 62)
    }

    // MARK: - Role Filtering

    @Test func correctLeaderCount() {
        let leaders = CardDatabase.shared.cards(forRole: .leader)
        #expect(leaders.count == 13)
        #expect(leaders.allSatisfy { $0.role == .leader })
    }

    @Test func correctGuardianCount() {
        let guardians = CardDatabase.shared.cards(forRole: .guardian)
        #expect(guardians.count == 18)
        #expect(guardians.allSatisfy { $0.role == .guardian })
    }

    @Test func correctAssassinCount() {
        let assassins = CardDatabase.shared.cards(forRole: .assassin)
        #expect(assassins.count == 18)
        #expect(assassins.allSatisfy { $0.role == .assassin })
    }

    @Test func correctTraitorCount() {
        let traitors = CardDatabase.shared.cards(forRole: .traitor)
        #expect(traitors.count == 13)
        #expect(traitors.allSatisfy { $0.role == .traitor })
    }

    @Test func roleCountsSumToTotal() {
        let db = CardDatabase.shared
        let total = Role.allCases.reduce(0) { $0 + db.cards(forRole: $1).count }
        #expect(total == db.allCards.count)
    }

    // MARK: - Lookup

    @Test func findCardById() {
        let db = CardDatabase.shared
        guard let first = db.allCards.first else {
            Issue.record("No cards loaded")
            return
        }
        let found = db.card(withId: first.id)
        #expect(found?.id == first.id)
        #expect(found?.name == first.name)
    }

    @Test func returnsNilForMissingId() {
        #expect(CardDatabase.shared.card(withId: "nonexistent") == nil)
    }

    // MARK: - Rarity Filtering

    @Test func rarityFilterReturnsCorrectCards() {
        let db = CardDatabase.shared
        for rarity in Rarity.allCases {
            let cards = db.cards(forRarity: rarity)
            #expect(cards.allSatisfy { $0.rarity == rarity })
        }
    }

    @Test func rarityCountsSumToTotal() {
        let db = CardDatabase.shared
        let total = Rarity.allCases.reduce(0) { $0 + db.cards(forRarity: $1).count }
        #expect(total == db.allCards.count)
    }

    // MARK: - Random Selection

    @Test func randomCardsRespectsCount() {
        let cards = CardDatabase.shared.randomCards(forRole: .assassin, count: 3)
        #expect(cards.count == 3)
        #expect(cards.allSatisfy { $0.role == .assassin })
    }

    @Test func randomCardsReturnsUniqueCards() {
        let cards = CardDatabase.shared.randomCards(forRole: .leader, count: 5)
        let ids = Set(cards.map(\.id))
        #expect(ids.count == cards.count)
    }

    @Test func randomCardsClampedToAvailable() {
        let cards = CardDatabase.shared.randomCards(forRole: .leader, count: 100)
        #expect(cards.count == 13) // Only 13 leaders exist
    }

    // MARK: - Card Data Integrity

    @Test func allCardsHaveUniqueIds() {
        let ids = CardDatabase.shared.allCards.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allCardsHaveUniqueCardNumbers() {
        let numbers = CardDatabase.shared.allCards.map(\.cardNumber)
        #expect(Set(numbers).count == numbers.count)
    }

    @Test func allCardsHaveNonEmptyNames() {
        for card in CardDatabase.shared.allCards {
            #expect(!card.name.isEmpty)
        }
    }

    @Test func allCardsHaveNonEmptyAbilityText() {
        for card in CardDatabase.shared.allCards {
            #expect(!card.abilityText.isEmpty)
        }
    }
}
