package com.solomon.treachery.data

import com.solomon.treachery.model.PlaneCard

interface PlaneDatabase {
    val allCards: List<PlaneCard>
    val allPlanes: List<PlaneCard>
    fun plane(withId: String): PlaneCard?
    fun randomPlane(excluding: Set<String>): PlaneCard?
}
