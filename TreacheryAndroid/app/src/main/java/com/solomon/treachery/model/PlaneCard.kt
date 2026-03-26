package com.solomon.treachery.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PlaneCard(
    val id: String,
    val name: String,
    @SerialName("type_line") val typeLine: String,
    @SerialName("oracle_text") val oracleText: String,
    @SerialName("image_uri") val imageUri: String? = null,
    @SerialName("is_phenomenon") val isPhenomenon: Boolean
)
