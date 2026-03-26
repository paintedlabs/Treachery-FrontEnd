import Foundation

protocol CardLookupProviding {
    var allCards: [IdentityCard] { get }
    func card(withId id: String) -> IdentityCard?
    func cards(forRole role: Role) -> [IdentityCard]
    func cards(forRarity rarity: Rarity) -> [IdentityCard]
    func randomCards(forRole role: Role, count: Int) -> [IdentityCard]
}
