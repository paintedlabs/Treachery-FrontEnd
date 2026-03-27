package com.solomon.treachery.mocks

import com.solomon.treachery.data.CardDatabase
import com.solomon.treachery.model.IdentityCard
import com.solomon.treachery.model.Rarity
import com.solomon.treachery.model.Role

class MockCardDatabase : CardDatabase {

    var cards: List<IdentityCard> = emptyList()

    override val allCards: List<IdentityCard>
        get() = cards

    override fun card(withId: String): IdentityCard? {
        return cards.find { it.id == withId }
    }

    override fun cards(forRole: Role): List<IdentityCard> {
        return cards.filter { it.role == forRole.value }
    }

    override fun cards(forRarity: Rarity): List<IdentityCard> {
        return cards.filter { it.rarity == forRarity.value }
    }

    override fun randomCards(forRole: Role, count: Int): List<IdentityCard> {
        return cards(forRole).shuffled().take(count)
    }
}
