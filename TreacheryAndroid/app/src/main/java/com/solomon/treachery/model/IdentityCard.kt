package com.solomon.treachery.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class IdentityCard(
    val id: String,
    @SerialName("card_number") val cardNumber: Int,
    val name: String,
    val role: String,
    @SerialName("ability_text") val abilityText: String,
    @SerialName("unveil_cost") val unveilCost: String,
    val rarity: String,
    @SerialName("has_undercover") val hasUndercover: Boolean,
    @SerialName("undercover_condition") val undercoverCondition: String? = null,
    @SerialName("timing_restriction") val timingRestriction: String? = null,
    @SerialName("life_modifier") val lifeModifier: Int? = null,
    @SerialName("hand_size_modifier") val handSizeModifier: Int? = null,
    @SerialName("flavor_text") val flavorText: String? = null,
    @SerialName("image_asset_name") val imageAssetName: String? = null
) {
    val roleEnum: Role? get() = Role.fromValue(role)
    val rarityEnum: Rarity? get() = Rarity.fromValue(rarity)
}
