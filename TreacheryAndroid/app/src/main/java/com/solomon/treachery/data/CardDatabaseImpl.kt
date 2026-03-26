package com.solomon.treachery.data

import android.content.Context
import com.solomon.treachery.model.IdentityCard
import com.solomon.treachery.model.Rarity
import com.solomon.treachery.model.Role
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CardDatabaseImpl @Inject constructor(
    @ApplicationContext private val context: Context
) : CardDatabase {

    private val json = Json { ignoreUnknownKeys = true }

    override val allCards: List<IdentityCard> by lazy {
        val jsonString = context.assets.open("identity_cards.json")
            .bufferedReader()
            .use { it.readText() }
        json.decodeFromString<List<IdentityCard>>(jsonString)
    }

    override fun card(withId: String): IdentityCard? {
        return allCards.find { it.id == withId }
    }

    override fun cards(forRole: Role): List<IdentityCard> {
        return allCards.filter { it.role == forRole.value }
    }

    override fun cards(forRarity: Rarity): List<IdentityCard> {
        return allCards.filter { it.rarity == forRarity.value }
    }

    override fun randomCards(forRole: Role, count: Int): List<IdentityCard> {
        return cards(forRole).shuffled().take(count)
    }
}
