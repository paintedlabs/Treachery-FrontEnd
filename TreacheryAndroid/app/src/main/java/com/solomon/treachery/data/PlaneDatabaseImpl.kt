package com.solomon.treachery.data

import android.content.Context
import com.solomon.treachery.model.PlaneCard
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlaneDatabaseImpl @Inject constructor(
    @ApplicationContext private val context: Context
) : PlaneDatabase {

    private val json = Json { ignoreUnknownKeys = true }

    override val allCards: List<PlaneCard> by lazy {
        val jsonString = context.assets.open("plane_cards.json")
            .bufferedReader()
            .use { it.readText() }
        json.decodeFromString<List<PlaneCard>>(jsonString)
    }

    override val allPlanes: List<PlaneCard>
        get() = allCards.filter { !it.isPhenomenon }

    override fun plane(withId: String): PlaneCard? {
        return allCards.find { it.id == withId }
    }

    override fun randomPlane(excluding: Set<String>): PlaneCard? {
        return allPlanes.filter { it.id !in excluding }.randomOrNull()
    }
}
