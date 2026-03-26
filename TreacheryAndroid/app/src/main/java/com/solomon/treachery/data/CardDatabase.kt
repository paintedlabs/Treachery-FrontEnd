package com.solomon.treachery.data

import com.solomon.treachery.model.IdentityCard
import com.solomon.treachery.model.Rarity
import com.solomon.treachery.model.Role

interface CardDatabase {
    val allCards: List<IdentityCard>
    fun card(withId: String): IdentityCard?
    fun cards(forRole: Role): List<IdentityCard>
    fun cards(forRarity: Rarity): List<IdentityCard>
    fun randomCards(forRole: Role, count: Int): List<IdentityCard>
}
