import Testing
import Foundation
@testable import Treachery_iOS

struct RarityTests {

    @Test func allCases() {
        #expect(Rarity.allCases.count == 4)
    }

    @Test func displayNames() {
        #expect(Rarity.uncommon.displayName == "Uncommon")
        #expect(Rarity.rare.displayName == "Rare")
        #expect(Rarity.mythic.displayName == "Mythic")
        #expect(Rarity.special.displayName == "Special")
    }

    @Test func identifiableUsesRawValue() {
        for rarity in Rarity.allCases {
            #expect(rarity.id == rarity.rawValue)
        }
    }

    @Test func codableRoundTrip() throws {
        for rarity in Rarity.allCases {
            let data = try JSONEncoder().encode(rarity)
            let decoded = try JSONDecoder().decode(Rarity.self, from: data)
            #expect(decoded == rarity)
        }
    }
}
