package com.solomon.treachery.ui.game

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.theme.*

@Composable
fun IdentityCardSheet(card: IdentityCard, player: Player, onDismiss: () -> Unit) {
    val roleColor = player.role?.roleColor ?: MtgGold
    val rarityColor = when (card.rarityEnum) {
        Rarity.UNCOMMON -> MtgSuccess
        Rarity.RARE -> MtgGuardian
        Rarity.MYTHIC -> MtgGold
        Rarity.SPECIAL -> MtgTraitor
        else -> MtgTextSecondary
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Scaffold(
            containerColor = MtgBackground,
            topBar = {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) { Text("Done", color = MtgGold) }
                }
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp)
            ) {
                // Card frame
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(MtgSurface)
                        .border(2.dp, roleColor, RoundedCornerShape(12.dp))
                ) {
                    // Title bar
                    Row(
                        modifier = Modifier.fillMaxWidth().background(MtgCardElevated).padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(card.name, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, color = MtgTextPrimary)
                        Text("#${card.cardNumber}", fontSize = 12.sp, color = MtgTextSecondary)
                    }
                    HorizontalDivider(color = MtgDivider)

                    // Role & Rarity
                    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Box(Modifier.size(10.dp).clip(CircleShape).background(roleColor))
                            Text(player.role?.displayName ?: "Unknown", fontWeight = FontWeight.SemiBold, color = roleColor, fontSize = 14.sp)
                        }
                        Text(card.rarityEnum?.displayName ?: card.rarity, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = rarityColor)
                    }
                    HorizontalDivider(color = MtgDivider)

                    // Ability text
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Ability", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = MtgGold)
                        Spacer(Modifier.height(8.dp))
                        Text(card.abilityText, color = MtgTextPrimary)
                    }
                    HorizontalDivider(color = MtgDivider)

                    // Unveil cost
                    Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Visibility, null, tint = roleColor)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("Unveil Cost", fontSize = 12.sp, color = MtgTextSecondary)
                            Text(card.unveilCost, fontWeight = FontWeight.Medium, color = MtgTextPrimary)
                        }
                        Spacer(Modifier.weight(1f))
                        if (player.isUnveiled) {
                            Text("UNVEILED", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = MtgBackground,
                                modifier = Modifier.background(roleColor, RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 4.dp))
                        }
                    }

                    // Undercover
                    if (card.hasUndercover && card.undercoverCondition != null) {
                        HorizontalDivider(color = MtgDivider)
                        Row(modifier = Modifier.padding(16.dp)) {
                            Icon(Icons.Default.TheaterComedy, null, tint = MtgTraitor)
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text("Undercover", fontSize = 12.sp, color = MtgTextSecondary)
                                Text(card.undercoverCondition!!, color = MtgTextPrimary)
                            }
                        }
                    }

                    // Timing
                    card.timingRestriction?.let { timing ->
                        HorizontalDivider(color = MtgDivider)
                        Row(modifier = Modifier.padding(16.dp)) {
                            Icon(Icons.Default.Schedule, null, tint = MtgGold)
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text("Timing", fontSize = 12.sp, color = MtgTextSecondary)
                                Text(timing, color = MtgTextPrimary)
                            }
                        }
                    }

                    // Modifiers
                    if (card.lifeModifier != null || card.handSizeModifier != null) {
                        HorizontalDivider(color = MtgDivider)
                        Row(modifier = Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                            card.lifeModifier?.let { life ->
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Icon(Icons.Default.Favorite, null, tint = MtgError, modifier = Modifier.size(16.dp))
                                    Text(if (life >= 0) "+$life" else "$life", fontWeight = FontWeight.SemiBold, color = MtgTextPrimary)
                                    Text("Life", fontSize = 12.sp, color = MtgTextSecondary)
                                }
                            }
                            card.handSizeModifier?.let { hand ->
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Icon(Icons.Default.PanTool, null, tint = MtgGuardian, modifier = Modifier.size(16.dp))
                                    Text(if (hand >= 0) "+$hand" else "$hand", fontWeight = FontWeight.SemiBold, color = MtgTextPrimary)
                                    Text("Hand Size", fontSize = 12.sp, color = MtgTextSecondary)
                                }
                            }
                        }
                    }

                    // Flavor text
                    card.flavorText?.takeIf { it.isNotEmpty() }?.let { flavor ->
                        HorizontalDivider(color = MtgDivider)
                        Text(flavor, fontSize = 12.sp, fontStyle = FontStyle.Italic, color = MtgTextSecondary,
                            modifier = Modifier.padding(16.dp))
                    }
                }

                // Win condition
                Spacer(Modifier.height(16.dp))
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Text("Win Condition", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = MtgGold)
                    Spacer(Modifier.height(4.dp))
                    Text(player.role?.winConditionText ?: "", fontSize = 14.sp, color = MtgTextSecondary, textAlign = TextAlign.Center)
                }
            }
        }
    }
}
