package com.solomon.treachery.mocks

import com.solomon.treachery.data.PlaneDatabase
import com.solomon.treachery.model.PlaneCard

class MockPlaneDatabase : PlaneDatabase {

    var cards: List<PlaneCard> = emptyList()

    override val allCards: List<PlaneCard>
        get() = cards

    override val allPlanes: List<PlaneCard>
        get() = cards.filter { !it.isPhenomenon }

    override fun plane(withId: String): PlaneCard? {
        return cards.find { it.id == withId }
    }

    override fun randomPlane(excluding: Set<String>): PlaneCard? {
        return allPlanes.filter { it.id !in excluding }.randomOrNull()
    }
}
